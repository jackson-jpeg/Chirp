@preconcurrency import AVFoundation
import Observation
import OSLog

@Observable
final class AudioEngine {
    var onEncodedAudio: (@Sendable (Data) -> Void)?
    private(set) var inputLevel: Float = 0.0

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

    private let targetFormat: AVAudioFormat
    private let samplesPerFrame = Constants.Opus.samplesPerFrame

    init() {
        self.targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Constants.Opus.sampleRate,
            channels: 1,
            interleaved: true
        )!
    }

    func setup(echoCancel: Bool = false) throws {
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

        let playbackFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Constants.Opus.sampleRate,
            channels: 1,
            interleaved: false
        )!
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

    func startCapture() {
        guard let engine, !isCapturing else { return }

        isCapturing = true
        captureAccumulator.removeAll()
        sequenceNumber = 0

        let inputNode = engine.inputNode

        // IMPORTANT: Pass nil format to installTap.
        // inputNode.outputFormat can LIE (reports 24kHz when hardware is 48kHz).
        // On repeated taps, iOS detects the mismatch and crashes with
        // "Failed to create tap due to format mismatch".
        // nil format = "give me whatever format you have" — always safe.
        converter = nil

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) {
            [weak self] buffer, _ in
            guard let self, self.isCapturing else { return }
            guard buffer.frameLength > 0 else { return }

            // Update level on audio thread (fast)
            self.updateInputLevelFromRawBuffer(buffer)

            // Process on separate queue to avoid blocking audio thread
            nonisolated(unsafe) let buf = buffer
            self.processingQueue.async { [weak self] in
                guard let self, self.isCapturing else { return }

                // Create converter lazily from actual buffer format
                let fmt = buf.format
                if self.converter == nil && fmt.sampleRate > 0 {
                    if fmt.sampleRate != Constants.Opus.sampleRate || fmt.channelCount != 1 || fmt.commonFormat != .pcmFormatInt16 {
                        self.converter = AVAudioConverter(from: fmt, to: self.targetFormat)
                        Logger.audio.info("Converter: \(fmt.sampleRate)Hz/\(fmt.channelCount)ch -> 16000Hz/1ch")
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
        jitterBuffer?.reset()
    }

    func receiveAudioPacket(_ opusData: Data, sequenceNumber: UInt32) {
        guard let codec, let playerNode else {
            Logger.audio.warning("receiveAudioPacket: codec or playerNode nil")
            return
        }

        do {
            // Decode Opus → Int16 PCM
            let pcmBuffer = try codec.decode(opusData)

            // Convert Int16 → Float32 for the player node
            let floatFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Constants.Opus.sampleRate,
                channels: 1,
                interleaved: false
            )!
            guard let floatBuffer = AVAudioPCMBuffer(
                pcmFormat: floatFormat,
                frameCapacity: pcmBuffer.frameLength
            ) else { return }
            floatBuffer.frameLength = pcmBuffer.frameLength

            if let int16Data = pcmBuffer.int16ChannelData,
               let floatData = floatBuffer.floatChannelData {
                for i in 0..<Int(pcmBuffer.frameLength) {
                    floatData[0][i] = Float(int16Data[0][i]) / Float(Int16.max)
                }
            }

            // Schedule on player node — plays immediately
            playerNode.scheduleBuffer(floatBuffer)

            // Start playing if not already
            if !playerNode.isPlaying {
                playerNode.play()
            }

            if sequenceNumber < 5 || sequenceNumber % 50 == 0 {
                Logger.audio.info("Audio playing: seq=\(sequenceNumber), \(pcmBuffer.frameLength) frames")
            }
        } catch {
            Logger.audio.error("Decode failed seq=\(sequenceNumber): \(error.localizedDescription)")
        }
    }

    func teardown() {
        stopCapture()

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

            // Simple convert (not the input-block version which can deadlock)
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
