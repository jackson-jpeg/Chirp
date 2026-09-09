@preconcurrency import AVFoundation
import Observation
import os
import OSLog

/// `@unchecked Sendable` is required because AVAudioEngine tap callbacks run on the
/// audio I/O thread. Mutable state: `captureAccumulator` and `converter` are accessed
/// exclusively on `processingQueue`; `isCapturing` is read on the render thread and
/// the processing queue, so it lives behind an `OSAllocatedUnfairLock`; `inputLevel`
/// is a display-only float written from the processing queue (benign race for UI
/// animation).
@Observable
final class AudioEngine: @unchecked Sendable {
    var onEncodedAudio: (@Sendable (Data) -> Void)?
    var onDecodedPCM: ((AVAudioPCMBuffer) -> Void)?
    var onRawAudioBuffer: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?
    private(set) var inputLevel: Float = 0.0

    /// Current Opus encoder bitrate in bits per second (for UI display).
    private(set) var currentBitrate: Int = Constants.Opus.bitrate

    private var engine: AVAudioEngine?
    private var codec: OpusCodec?
    private var jitterBuffer: JitterBuffer?
    private var sourceNode: AVAudioSourceNode?
    private var playerNode: AVAudioPlayerNode?

    private var captureAccumulator: [Int16] = []
    private var sequenceNumber: UInt32 = 0
    private var converter: AVAudioConverter?

    /// Read on the audio render thread (the tap) and on `processingQueue`,
    /// written from the main actor in `startCapture`/`stopCapture`. A plain
    /// `Bool` here is a data race the sanitizer can actually hit — a torn read
    /// is vanishingly unlikely, but the unordered one means a tap callback can
    /// keep consuming after `stopCapture` believed it had fenced them out.
    private let capturingFlag = OSAllocatedUnfairLock(initialState: false)
    private var isCapturing: Bool {
        get { capturingFlag.withLock { $0 } }
        set { capturingFlag.withLock { $0 = newValue } }
    }
    private let processingQueue = DispatchQueue(label: "com.chirpchirp.audio.processing", qos: .userInteractive)
    private var playbackTimer: DispatchSourceTimer?
    private let playbackQueue = DispatchQueue(label: "com.chirpchirp.audio.playback", qos: .userInteractive)
    private var lastGoodFrame: Data?
    private var concealmentCount: Int = 0

    private let targetFormat: AVAudioFormat
    private let samplesPerFrame = Constants.Opus.samplesPerFrame

    init() {
        // 16kHz mono Int16 is universally supported on all iOS devices.
        // The guard is purely defensive — this initializer should never return nil for these parameters.
        if let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Constants.Opus.sampleRate,
            channels: 1,
            interleaved: true
        ) {
            self.targetFormat = format
        } else {
            // Absolute last resort — use 44.1kHz standard format.
            Logger.audio.error("Failed to create target audio format — using 44.1kHz fallback")
            guard let fallback = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)
                ?? AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false) else {
                fatalError("Cannot create any audio format — device configuration broken")
            }
            self.targetFormat = fallback
        }
    }

    func setup(echoCancel: Bool = true) throws {
        try AudioSessionManager.configure(echoCancel: echoCancel)

        let codec = try OpusCodec()
        let jitterBuffer = JitterBuffer()
        let engine = AVAudioEngine()

        self.codec = codec
        self.jitterBuffer = jitterBuffer

        // Playback: use AVAudioPlayerNode with scheduled buffers.
        // AVAudioSourceNode at 16kHz had resampling issues with the mixer.
        // PlayerNode + scheduled buffers handles format conversion reliably.
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)

        guard let playbackFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Constants.Opus.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            Logger.audio.error("Failed to create playback audio format")
            return
        }
        engine.connect(playerNode, to: engine.mainMixerNode, format: playbackFormat)

        self.playerNode = playerNode

        // CRITICAL: Access inputNode BEFORE engine.start() to force the audio
        // graph to include the input.
        let _ = engine.inputNode

        engine.prepare()
        try engine.start()

        // Start player node for playback
        playerNode.play()

        self.engine = engine
        Logger.audio.info("AudioEngine setup complete")
    }

    /// Restart the AVAudioEngine if iOS killed it during an interruption.
    /// Safe to call even if the engine is still running.
    func restartEngineIfNeeded() {
        guard let engine else {
            Logger.audio.warning("restartEngineIfNeeded: no engine")
            return
        }
        guard !engine.isRunning else { return }

        Logger.audio.warning("AVAudioEngine stopped after interruption — restarting")
        do {
            engine.prepare()
            try engine.start()
            playerNode?.play()
            Logger.audio.info("AVAudioEngine restarted successfully")
        } catch {
            Logger.audio.error("Failed to restart AVAudioEngine: \(error.localizedDescription)")
        }
    }

    func startCapture() {
        guard let engine, !isCapturing else { return }

        isCapturing = true

        // `converter` and `captureAccumulator` belong to `processingQueue`.
        // The queue is serial, so this reset is ordered before any `consume`
        // the new tap enqueues — same effect as resetting inline, without
        // touching queue-owned state from the main actor.
        // (Dropping the converter matters: pass nil format to installTap —
        // inputNode.outputFormat can LIE (reports 24kHz when hardware is
        // 48kHz), and on repeated taps iOS detects the mismatch and crashes
        // with "Failed to create tap due to format mismatch". nil format =
        // "give me whatever format you have" — so the converter must be
        // rebuilt from whatever format the new tap actually delivers.)
        processingQueue.async { [weak self] in
            self?.converter = nil
            self?.captureAccumulator.removeAll()
        }

        let inputNode = engine.inputNode

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) {
            [weak self] buffer, time in
            guard let self, self.isCapturing else { return }
            guard buffer.frameLength > 0 else { return }

            // COPY, then leave. `buffer` belongs to the audio engine and its
            // backing store is only valid for the duration of this callback —
            // the engine refills it as soon as we return. The previous code
            // handed this exact buffer to processingQueue and read it there,
            // which meant the samples it encoded were whatever the engine had
            // written since. `CapturedFrames` is numbers, so it outlives the
            // callback legitimately and crosses the queue as a Sendable value
            // rather than as a pointer with an escape hatch on it.
            guard let captured = CapturedFrames(copying: buffer, at: time) else {
                Logger.audio.warning("Unsupported tap format \(buffer.format) — dropping buffer")
                return
            }

            self.processingQueue.async { [weak self] in
                guard let self, self.isCapturing else { return }
                self.consume(captured)
            }
        }

        #if DEBUG
        AudioTelemetry.shared.mark("capture-start")
        #endif
        Logger.audio.info("Capture started")
    }

    func stopCapture() {
        guard let engine, isCapturing else { return }

        // Set flag FIRST so callbacks exit
        isCapturing = false
        // Remove tap immediately — callback will exit fast since
        // converter work is on processingQueue, not the audio thread
        engine.inputNode.removeTap(onBus: 0)
        // Clean up on processing queue to avoid race
        processingQueue.async { [weak self] in
            self?.converter = nil
            self?.captureAccumulator.removeAll()
        }

        #if DEBUG
        AudioTelemetry.shared.mark("capture-stop")
        #endif
        Logger.audio.info("Capture stopped")
    }

    func resetJitterBuffer() {
        stopPlaybackTimer()
        jitterBuffer?.reset()
    }

    func receiveAudioPacket(_ opusData: Data, sequenceNumber: UInt32) {
        guard let codec, let jitterBuffer else {
            Logger.audio.warning("receiveAudioPacket: codec or jitterBuffer nil")
            return
        }

        do {
            // Decode Opus → Int16 PCM, push into jitter buffer for reordering
            let pcmBuffer = try codec.decode(opusData)
            jitterBuffer.push(pcmBuffer: pcmBuffer, sequenceNumber: sequenceNumber)

            // Start playback timer if not already running
            if playbackTimer == nil {
                startPlaybackTimer()
            }

            if sequenceNumber < 5 || sequenceNumber % 50 == 0 {
                Logger.audio.info("Audio buffered: seq=\(sequenceNumber), buffered=\(jitterBuffer.bufferedCount)")
            }
        } catch {
            Logger.audio.error("Decode failed seq=\(sequenceNumber): \(error.localizedDescription)")
        }
    }

    // MARK: - Jitter Buffer Playback

    private func startPlaybackTimer() {
        guard playbackTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: playbackQueue)
        // Fire every 20ms (one Opus frame duration) for smooth playback
        timer.schedule(deadline: .now(), repeating: .milliseconds(20), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            self?.drainJitterBuffer()
        }
        timer.resume()
        playbackTimer = timer

        Logger.audio.info("Playback timer started")
    }

    private func stopPlaybackTimer() {
        playbackTimer?.cancel()
        playbackTimer = nil
    }

    private func drainJitterBuffer() {
        guard let jitterBuffer, let playerNode else { return }

        // Pull one frame (20ms) from the jitter buffer
        let pcmData: Data
        let attenuation: Float

        if let pulled = jitterBuffer.pull(frameCount: 1) {
            pcmData = pulled
            lastGoodFrame = pulled
            concealmentCount = 0
            attenuation = 1.0
        } else if let lastFrame = lastGoodFrame, concealmentCount < 3 {
            // Packet loss concealment: repeat last good frame with decay
            pcmData = lastFrame
            attenuation = Float(3 - concealmentCount) / 3.0
            concealmentCount += 1
        } else {
            // No data and no concealment possible — silence / skip
            return
        }

        let sampleCount = pcmData.count / MemoryLayout<Int16>.size
        guard sampleCount > 0 else { return }

        // Convert Int16 data → Float32 AVAudioPCMBuffer for playerNode
        guard let floatFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Constants.Opus.sampleRate,
            channels: 1,
            interleaved: false
        ) else { return }

        guard let floatBuffer = AVAudioPCMBuffer(
            pcmFormat: floatFormat,
            frameCapacity: AVAudioFrameCount(sampleCount)
        ) else { return }
        floatBuffer.frameLength = AVAudioFrameCount(sampleCount)

        guard let floatData = floatBuffer.floatChannelData else { return }
        pcmData.withUnsafeBytes { rawPtr in
            guard let int16Ptr = rawPtr.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
            for i in 0..<sampleCount {
                floatData[0][i] = Float(int16Ptr[i]) / Float(Int16.max) * attenuation
            }
        }

        // Feed decoded PCM to live transcription (if wired)
        onDecodedPCM?(floatBuffer)

        #if DEBUG
        // Receive-side envelope. This is the LAST point at which the audio is
        // visible to software — everything after `scheduleBuffer` is inside
        // AVAudioEngine and then the hardware. An assertion here therefore
        // means "the app produced this signal and handed it to the OS to play",
        // which is the strongest claim any automated check can make. Whether it
        // reached a speaker is not knowable from in here; see
        // DEVICE-TEST-AUTOMATION.md, "What cannot be automated".
        if let rms = AudioTelemetry.rms(of: floatBuffer) {
            AudioTelemetry.shared.recordPlayback(rms: rms)
        }
        #endif

        // Schedule on player node
        playerNode.scheduleBuffer(floatBuffer)

        // Start playing if not already
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    func teardown() {
        stopCapture()
        stopPlaybackTimer()

        playerNode?.stop()
        engine?.stop()
        if let node = sourceNode {
            engine?.detach(node)
        }
        if let node = playerNode {
            engine?.detach(node)
        }
        sourceNode = nil
        playerNode = nil
        engine = nil
        codec = nil

        jitterBuffer?.reset()
        jitterBuffer = nil

        AudioSessionManager.deactivate()
        Logger.audio.info("AudioEngine torn down")
    }

    // MARK: - Adaptive Bitrate

    /// Dynamically adjust the Opus encoder bitrate based on link quality.
    /// Thread-safe: dispatches to the processing queue where the codec is accessed.
    func setTargetBitrate(_ bitsPerSecond: Int) {
        processingQueue.async { [weak self] in
            guard let self, let codec = self.codec else { return }
            codec.setTargetBitrate(bitsPerSecond)
            let newBitrate = codec.currentBitrate
            Task { @MainActor [weak self] in
                self?.currentBitrate = newBitrate
            }
        }
    }

    // MARK: - Captured Frames

    /// One tap callback's samples, lifted out of the audio engine's storage.
    ///
    /// The engine owns the buffer it passes to a tap and refills it the moment
    /// the callback returns, so anything that outlives the callback must copy
    /// rather than retain. This is that copy: plain numbers plus the few format
    /// facts needed to rebuild an `AVAudioPCMBuffer` on the far side, which
    /// makes it `Sendable` by construction rather than by assertion.
    ///
    /// Channel 0 only. Every device this app runs on captures mono, and the
    /// pipeline downstream has always taken `channelData[0]` anyway.
    /// Internal rather than private purely so the tests can reach it: the whole
    /// point of this type is that a copy survives the engine overwriting the
    /// original, and that is not observable through AudioEngine's public surface
    /// without real capture hardware.
    struct CapturedFrames: Sendable {
        enum Samples: Sendable {
            case float32([Float])
            case int16([Int16])
        }

        let samples: Samples
        let sampleRate: Double
        let frameCount: AVAudioFrameCount
        let sampleTime: AVAudioFramePosition

        init?(copying buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
            let frames = Int(buffer.frameLength)
            guard frames > 0, buffer.format.sampleRate > 0 else { return nil }

            if let channels = buffer.floatChannelData {
                samples = .float32(Array(UnsafeBufferPointer(start: channels[0], count: frames)))
            } else if let channels = buffer.int16ChannelData {
                samples = .int16(Array(UnsafeBufferPointer(start: channels[0], count: frames)))
            } else {
                // Int32 and other exotic formats are not produced by any input
                // hardware we support. Declining loudly beats copying garbage.
                return nil
            }

            sampleRate = buffer.format.sampleRate
            frameCount = buffer.frameLength
            sampleTime = time.sampleTime
        }

        /// Rebuild a mono `AVAudioPCMBuffer` owned entirely by the caller.
        func makeBuffer() -> AVAudioPCMBuffer? {
            let commonFormat: AVAudioCommonFormat
            switch samples {
            case .float32: commonFormat = .pcmFormatFloat32
            case .int16:   commonFormat = .pcmFormatInt16
            }
            guard let format = AVAudioFormat(
                commonFormat: commonFormat,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            ), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                return nil
            }
            buffer.frameLength = frameCount

            switch samples {
            case .float32(let values):
                guard let dest = buffer.floatChannelData else { return nil }
                values.withUnsafeBufferPointer { dest[0].update(from: $0.baseAddress!, count: values.count) }
            case .int16(let values):
                guard let dest = buffer.int16ChannelData else { return nil }
                values.withUnsafeBufferPointer { dest[0].update(from: $0.baseAddress!, count: values.count) }
            }
            return buffer
        }

        /// RMS level for the waveform, computed from the copy.
        var rmsLevel: Float {
            let sumOfSquares: Float
            let count: Int
            switch samples {
            case .float32(let values):
                count = values.count
                sumOfSquares = values.reduce(0) { $0 + $1 * $1 }
            case .int16(let values):
                count = values.count
                sumOfSquares = values.reduce(0) {
                    let normalized = Float($1) / Float(Int16.max)
                    return $0 + normalized * normalized
                }
            }
            guard count > 0 else { return 0 }
            return min(1.0, sqrt(sumOfSquares / Float(count)) * 5.0)
        }
    }

    // MARK: - Private

    /// Everything the tap used to do inline on the audio I/O thread. Runs on
    /// `processingQueue`: the level maths, the client callback, the converter
    /// setup and the encode. A real-time thread must not allocate, take locks,
    /// or call unbounded client code, and the tap closure did all three.
    private func consume(_ captured: CapturedFrames) {
        inputLevel = captured.rmsLevel

        #if DEBUG
        // Send-side envelope for the device harness. Recorded here rather than
        // in the tap because the tap is the render thread.
        AudioTelemetry.shared.recordCapture(rms: captured.rmsLevel)
        #endif

        guard let buffer = captured.makeBuffer() else {
            Logger.audio.warning("Could not rebuild captured buffer — dropping")
            return
        }

        // Client callback now receives a buffer this method exclusively owns,
        // off the render thread. Consumers previously had to make their own
        // copy of a buffer that was already stale by the time they saw it.
        if let onRawAudioBuffer {
            let time = AVAudioTime(sampleTime: captured.sampleTime, atRate: captured.sampleRate)
            onRawAudioBuffer(buffer, time)
        }

        let fmt = buffer.format
        if converter == nil,
           fmt.sampleRate != Constants.Opus.sampleRate
            || fmt.channelCount != 1
            || fmt.commonFormat != .pcmFormatInt16 {
            converter = AVAudioConverter(from: fmt, to: targetFormat)
            Logger.audio.info("Converter created: \(fmt.sampleRate)Hz/\(fmt.channelCount)ch/fmt\(fmt.commonFormat.rawValue) -> 16kHz/1ch/Int16")
        }

        processInputBuffer(buffer)
    }

    private func processInputBuffer(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }

        if let converter {
            // Convert from hardware format to 16kHz mono Int16.
            // Output capacity: input frames / sample rate ratio + padding
            let ratio = Constants.Opus.sampleRate / buffer.format.sampleRate
            let outputFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1

            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: max(outputFrames, AVAudioFrameCount(samplesPerFrame))
            ) else { return }

            // Simple convert (not the input-block version which can deadlock).
            // nonisolated(unsafe) is safe here: the converter closure runs synchronously
            // within convert() on the same thread, so no actual data race can occur.
            var error: NSError?
            nonisolated(unsafe) var consumed = false
            nonisolated(unsafe) let src = buffer
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                if !consumed {
                    consumed = true
                    outStatus.pointee = .haveData
                    return src
                }
                outStatus.pointee = .endOfStream
                return nil
            }

            guard status != .error, error == nil, convertedBuffer.frameLength > 0 else {
                return
            }

            // Extract Int16 samples from converted buffer
            guard let channelData = convertedBuffer.int16ChannelData else { return }
            let frameLength = Int(convertedBuffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            accumulateAndEncode(samples)
        } else {
            // Already in target format
            guard let channelData = buffer.int16ChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            accumulateAndEncode(samples)
        }
    }

    private func accumulateAndEncode(_ samples: [Int16]) {
        // The input level is set once, in consume(), from the raw captured
        // frames. It used to be recomputed here from the post-conversion
        // samples as well, so two different measurements of the same audio
        // raced to be the one the waveform showed.
        // Accumulate samples until we have a full frame
        captureAccumulator.append(contentsOf: samples)

        while captureAccumulator.count >= samplesPerFrame {
            let frameSamples = Array(captureAccumulator.prefix(samplesPerFrame))
            captureAccumulator.removeFirst(samplesPerFrame)

            // Create PCM buffer for encoding
            guard let encodeBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: AVAudioFrameCount(samplesPerFrame)
            ) else { continue }

            encodeBuffer.frameLength = AVAudioFrameCount(samplesPerFrame)
            if let dest = encodeBuffer.int16ChannelData {
                frameSamples.withUnsafeBufferPointer { src in
                    dest[0].update(from: src.baseAddress!, count: samplesPerFrame)
                }
            }

            // Encode with Opus
            guard let codec else { return }
            do {
                let encodedData = try codec.encode(encodeBuffer)
                sequenceNumber += 1
                onEncodedAudio?(encodedData)
            } catch {
                Logger.audio.error("Opus encode failed: \(error.localizedDescription)")
            }
        }
    }


}
