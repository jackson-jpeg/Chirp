@preconcurrency import AVFoundation
import ChirpCore
import Foundation
import os

/// Live voice: microphone to 20 ms Opus frames, and Opus frames from the
/// line back to the speaker, through ChirpCore's per-speaker `JitterBuffer`.
///
/// Carried over from 1.0 and rewritten clean (audit section 7): the copy out
/// of the render thread (`CapturedFrames`), one persistent converter fed
/// `.noDataNow` (never `.endOfStream`, which made 1.0 send only the first
/// 100 ms of each press), the DEBUG sine mic. Changed: the jitter buffer
/// resets for a new speaker (ChirpCore), the playback timer stops when the
/// line goes quiet, and nothing here touches the audio session. The engine
/// runs only between `start()` and `stop()`, which the owner calls when
/// `AudioSession` has the session open (2.5.4).
///
/// Threads: `start`, `stop`, `startCapture`, `stopCapture` on the main actor;
/// the tap copies and leaves; encoding on `captureQueue`; decoding, the
/// jitter buffer and scheduling on `playbackQueue`. Each queue owns its state.
final class VoiceEngine: @unchecked Sendable {
    /// An encoded frame, on the capture queue. The owner sends it.
    var onFrame: (@Sendable (Data) -> Void)?
    /// Each played 20 ms frame (Float32, 16 kHz) and whose it is, on the
    /// playback queue: live captions read it.
    var onPlayed: (@Sendable (JitterBuffer.Speaker, AVAudioPCMBuffer) -> Void)?
    /// Your own voice while capturing, as 16 kHz Int16 (`OpusCodec.pcmFormat`),
    /// on the capture queue: your live caption reads it.
    var onCaptured: (@Sendable (AVAudioPCMBuffer) -> Void)?
    /// A speaker's stream went quiet, on the playback queue.
    var onStreamEnded: (@Sendable (JitterBuffer.Speaker) -> Void)?

    private struct Flags { var capturing = false; var playsAudio = true; var level: Float = 0 }
    private let flags = OSAllocatedUnfairLock(initialState: Flags())

    /// False in "captions only": frames are decoded and captioned, not played.
    var playsAudio: Bool {
        get { flags.withLock { $0.playsAudio } }
        set { flags.withLock { $0.playsAudio = newValue } }
    }
    /// The microphone level, 0...1, while capturing.
    var level: Float { flags.withLock { $0.level } }
    private var capturing: Bool {
        get { flags.withLock { $0.capturing } }
        set { flags.withLock { $0.capturing = newValue } }
    }

    // Main actor.
    private var engine: AVAudioEngine?
    private var hasInput = false
    /// Set on main, read on the playback queue.
    private let playerLock = NSLock()
    private var _player: AVAudioPlayerNode?
    private var player: AVAudioPlayerNode? {
        get { playerLock.withLock { _player } }
        set { playerLock.withLock { _player = newValue } }
    }

    static let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: OpusCodec.sampleRate,
                                              channels: 1, interleaved: false)!

    // Capture queue.
    private let captureQueue = DispatchQueue(label: "chirpchirps.voice.capture", qos: .userInteractive)
    private var encoder: OpusCodec?
    private var converter: AVAudioConverter?
    private var accumulator: [Int16] = []
    #if DEBUG
    private static let sineMic = UserDefaults.standard.bool(forKey: "ChirpSineMic")
    private var sinePosition: Int64 = 0
    #endif

    // Playback queue.
    private let playbackQueue = DispatchQueue(label: "chirpchirps.voice.playback", qos: .userInteractive)
    private var decoder: OpusCodec?
    private var jitter = JitterBuffer()
    private var timer: DispatchSourceTimer?
    private var concealed = 0
    private var quietFrames = 0
    /// After this many empty 20 ms ticks the stream is over and the timer stops.
    static let quietLimit = 25

    var running: Bool { engine?.isRunning == true }

    // MARK: Engine

    /// Builds and starts the engine. Call only with the session open: `input`
    /// only under the record session (the playback session has no microphone,
    /// and an engine that touched `inputNode` there fails to start).
    @MainActor
    func start(input: Bool) throws {
        if let engine, engine.isRunning, hasInput == input { return }
        if engine != nil { stop() }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: Self.playbackFormat)
        if input { _ = engine.inputNode }   // before start, so the graph includes the input
        engine.prepare()
        try engine.start()
        player.play()
        self.engine = engine
        self.player = player
        hasInput = input
        captureQueue.async { if self.encoder == nil { self.encoder = try? OpusCodec() } }
        playbackQueue.async { if self.decoder == nil { self.decoder = try? OpusCodec() } }
    }

    /// Stops everything; the session can close after this.
    @MainActor
    func stop() {
        stopCapture()
        player?.stop()
        engine?.stop()
        engine = nil
        player = nil
        hasInput = false
        playbackQueue.async { self.endStream() }
    }

    // MARK: Capture

    @MainActor
    func startCapture() {
        guard let engine, engine.isRunning, hasInput, !capturing else { return }
        capturing = true
        // The converter is rebuilt from whatever format the new tap delivers
        // (`format: nil`: the input node's reported format can be wrong, and a
        // mismatched tap crashes).
        captureQueue.async { self.converter = nil; self.accumulator.removeAll() }
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self, self.capturing, let copy = CapturedFrames(copying: buffer) else { return }
            self.captureQueue.async { if self.capturing { self.consume(copy) } }
        }
    }

    @MainActor
    func stopCapture() {
        guard capturing else { return }
        capturing = false
        engine?.inputNode.removeTap(onBus: 0)
        flags.withLock { $0.level = 0 }
        captureQueue.async { self.converter = nil; self.accumulator.removeAll() }
    }

    private func consume(_ captured: CapturedFrames) {
        var captured = captured
        #if DEBUG
        if Self.sineMic {
            captured = CapturedFrames(pulsedSineReplacing: captured, startingAt: sinePosition)
            sinePosition += Int64(captured.frameCount)
        }
        #endif
        let level = captured.level
        flags.withLock { $0.level = level }
        guard let buffer = captured.makeBuffer() else { return }

        let target = OpusCodec.pcmFormat
        let fmt = buffer.format
        if fmt.sampleRate == target.sampleRate, fmt.commonFormat == .pcmFormatInt16, fmt.channelCount == 1,
           let ch = buffer.int16ChannelData {
            onCaptured?(buffer)
            accumulate(Array(UnsafeBufferPointer(start: ch[0], count: Int(buffer.frameLength))))
            return
        }
        if converter == nil { converter = AVAudioConverter(from: fmt, to: target) }
        guard let converter else { return }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / fmt.sampleRate) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: max(capacity, AVAudioFrameCount(OpusCodec.samplesPerFrame)))
        else { return }
        var error: NSError?
        // The block runs synchronously inside convert(), on this queue.
        nonisolated(unsafe) var given = false
        nonisolated(unsafe) let source = buffer
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if !given {
                given = true
                outStatus.pointee = .haveData
                return source
            }
            // Never .endOfStream: this converter lives for the whole press.
            outStatus.pointee = .noDataNow
            return nil
        }
        guard status != .error, error == nil, out.frameLength > 0, let ch = out.int16ChannelData else { return }
        onCaptured?(out)
        accumulate(Array(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength))))
    }

    private func accumulate(_ samples: [Int16]) {
        accumulator.append(contentsOf: samples)
        let n = OpusCodec.samplesPerFrame
        guard let encoder else { return }
        while accumulator.count >= n {
            let frame = try? accumulator.withUnsafeBufferPointer { try encoder.encode(UnsafeBufferPointer(rebasing: $0[0..<n])) }
            accumulator.removeFirst(n)
            if let frame { onFrame?(frame) }
        }
    }

    // MARK: Playback

    /// An Opus frame off the line (already opened by dispatch).
    func receive(_ opus: Data, from speaker: JitterBuffer.Speaker, sequence: UInt32) {
        playbackQueue.async {
            guard let decoder = self.decoder, let pcm = try? decoder.decode(opus) else { return }
            self.jitter.push(pcm, sequence: sequence, from: speaker)
            self.startTimer()
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        quietFrames = 0
        let t = DispatchSource.makeTimerSource(queue: playbackQueue)
        t.schedule(deadline: .now(), repeating: .milliseconds(20), leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.drain() }
        t.resume()
        timer = t
    }

    private func drain() {
        guard let speaker = jitter.speaker else { endStream(); return }
        let pcm: Data
        if let frame = jitter.pull() {
            pcm = frame
            concealed = 0
            quietFrames = 0
        } else if concealed < 3, jitter.stats.received > 0, let fill = try? decoder?.conceal() {
            pcm = fill
            concealed += 1
            quietFrames += 1
        } else {
            quietFrames += 1
            if quietFrames >= Self.quietLimit { endStream() }
            return
        }
        guard let buffer = Self.floatBuffer(pcm) else { return }
        onPlayed?(speaker, buffer)
        if playsAudio, let player {
            player.scheduleBuffer(buffer)
            if !player.isPlaying { player.play() }
        }
    }

    /// The line went quiet: stop the timer and forget the stream.
    private func endStream() {
        timer?.cancel()
        timer = nil
        concealed = 0
        quietFrames = 0
        if let speaker = jitter.speaker { onStreamEnded?(speaker) }
        jitter.reset()
    }

    private static func floatBuffer(_ pcm: Data) -> AVAudioPCMBuffer? {
        let count = pcm.count / MemoryLayout<Int16>.size
        guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(count)),
              let dest = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(count)
        pcm.withUnsafeBytes { raw in
            let src = raw.bindMemory(to: Int16.self)
            for i in 0..<count { dest[0][i] = Float(src[i]) / Float(Int16.max) }
        }
        return buffer
    }
}
