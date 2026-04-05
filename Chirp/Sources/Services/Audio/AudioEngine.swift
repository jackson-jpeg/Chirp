@preconcurrency import AVFoundation
import Observation
import OSLog

/// `@unchecked Sendable` is required because AVAudioEngine tap callbacks run on the
/// audio I/O thread. Mutable state: `captureAccumulator` and `converter` are accessed
/// exclusively on `processingQueue`; `inputLevel` is a display-only float written from
/// the audio thread (benign race for UI animation).
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
    private var isCapturing = false
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
        captureAccumulator.removeAll()

        let inputNode = engine.inputNode

        // IMPORTANT: Pass nil format to installTap.
        // inputNode.outputFormat can LIE (reports 24kHz when hardware is 48kHz).
        // On repeated taps, iOS detects the mismatch and crashes with
        // "Failed to create tap due to format mismatch".
        // nil format = "give me whatever format you have" — always safe.
        converter = nil

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) {
            [weak self] buffer, time in
            guard let self, self.isCapturing else { return }
            guard buffer.frameLength > 0 else { return }

            // Update level on audio thread (fast)
            self.updateInputLevelFromRawBuffer(buffer)

            // Feed raw audio to sound analysis (if wired)
            self.onRawAudioBuffer?(buffer, time)

            // Process on separate queue to avoid blocking audio thread.
            // AVAudioPCMBuffer is not Sendable but is only read on processingQueue.
            nonisolated(unsafe) let buf = buffer
            self.processingQueue.async { [weak self] in
                guard let self, self.isCapturing else { return }

                // Create converter lazily from actual buffer format
                let fmt = buf.format
                if self.converter == nil {
                    if fmt.sampleRate > 0 && (fmt.sampleRate != Constants.Opus.sampleRate || fmt.channelCount != 1 || fmt.commonFormat != .pcmFormatInt16) {
                        self.converter = AVAudioConverter(from: fmt, to: self.targetFormat)
                        Logger.audio.info("Converter created: \(fmt.sampleRate)Hz/\(fmt.channelCount)ch/fmt\(fmt.commonFormat.rawValue) -> 16kHz/1ch/Int16")
                    } else if fmt.sampleRate == 0 {
                        Logger.audio.warning("Buffer has 0Hz format — skipping")
                        return
                    } else {
                        Logger.audio.info("No converter needed — buffer already 16kHz/1ch/Int16")
                    }
                }

                self.processInputBuffer(buf)
            }
        }

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

    // MARK: - Private

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

        // Update input level
        updateInputLevel(samples: samples)

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

    private func updateInputLevel(samples: [Int16]) {
        guard !samples.isEmpty else { return }

        var sumOfSquares: Float = 0
        for sample in samples {
            let normalized = Float(sample) / Float(Int16.max)
            sumOfSquares += normalized * normalized
        }
        let rms = sqrt(sumOfSquares / Float(samples.count))
        // Amplify for better visual feedback (raw RMS is usually 0.01-0.1)
        let amplified = min(1.0, rms * 5.0)
        inputLevel = amplified
    }

    /// Update input level directly from a raw AVAudioPCMBuffer in any format.
    /// Works before the converter is created — ensures waveform always responds.
    private func updateInputLevelFromRawBuffer(_ buffer: AVAudioPCMBuffer) {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        var rms: Float = 0

        if let floatData = buffer.floatChannelData {
            // Float32 format
            let samples = floatData[0]
            var sumOfSquares: Float = 0
            for i in 0..<frameLength {
                sumOfSquares += samples[i] * samples[i]
            }
            rms = sqrt(sumOfSquares / Float(frameLength))
        } else if let int16Data = buffer.int16ChannelData {
            // Int16 format
            let samples = int16Data[0]
            var sumOfSquares: Float = 0
            for i in 0..<frameLength {
                let normalized = Float(samples[i]) / Float(Int16.max)
                sumOfSquares += normalized * normalized
            }
            rms = sqrt(sumOfSquares / Float(frameLength))
        } else {
            return
        }

        let amplified = min(1.0, rms * 5.0)
        inputLevel = amplified
    }
}
