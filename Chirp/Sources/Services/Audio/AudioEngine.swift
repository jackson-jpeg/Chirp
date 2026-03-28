import AVFoundation
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

    private var captureAccumulator: [Int16] = []
    private var sequenceNumber: UInt32 = 0
    private var converter: AVAudioConverter?
    private var isCapturing = false

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

    func setup() throws {
        try AudioSessionManager.configure()

        let codec = try OpusCodec()
        let jitterBuffer = JitterBuffer()
        let engine = AVAudioEngine()

        self.codec = codec
        self.jitterBuffer = jitterBuffer

        // Playback source node: pulls decoded PCM from jitter buffer.
        // Runs at 16kHz mono Int16 — the engine handles resampling to hardware rate.
        let jb = jitterBuffer
        let playbackFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Constants.Opus.sampleRate,
            channels: 1,
            interleaved: true
        )!

        // Residual buffer for partial frame reads across render callbacks
        var residual = Data()
        let bytesPerSample = MemoryLayout<Int16>.size

        let node = AVAudioSourceNode(format: playbackFormat) { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let requestedBytes = Int(frameCount) * bytesPerSample
            var outputData = Data()

            // Drain residual from previous callback first
            if !residual.isEmpty {
                let take = min(residual.count, requestedBytes)
                outputData.append(residual.prefix(take))
                residual.removeFirst(take)
            }

            // Pull frames from jitter buffer until we have enough
            while outputData.count < requestedBytes {
                if let frame = jb.pull(frameCount: 1) {
                    let needed = requestedBytes - outputData.count
                    if frame.count <= needed {
                        outputData.append(frame)
                    } else {
                        outputData.append(frame.prefix(needed))
                        residual.append(frame.dropFirst(needed))
                    }
                } else {
                    break // No more data — fill remainder with silence
                }
            }

            // Copy to output buffers, zero-fill any shortfall
            for bufferIndex in 0..<ablPointer.count {
                let buf = ablPointer[bufferIndex]
                guard let dest = buf.mData else { continue }
                if outputData.count >= requestedBytes {
                    outputData.withUnsafeBytes { src in
                        dest.copyMemory(from: src.baseAddress!, byteCount: requestedBytes)
                    }
                } else {
                    // Partial data + silence
                    if !outputData.isEmpty {
                        outputData.withUnsafeBytes { src in
                            dest.copyMemory(from: src.baseAddress!, byteCount: outputData.count)
                        }
                    }
                    let silenceStart = dest.advanced(by: outputData.count)
                    memset(silenceStart, 0, requestedBytes - outputData.count)
                }
            }
            return noErr
        }

        self.sourceNode = node
        engine.attach(node)

        let mainMixer = engine.mainMixerNode
        engine.connect(node, to: mainMixer, format: playbackFormat)

        engine.prepare()
        try engine.start()

        self.engine = engine
        Logger.audio.info("AudioEngine setup complete")
    }

    func startCapture() {
        guard let engine, !isCapturing else { return }

        isCapturing = true
        captureAccumulator.removeAll()
        sequenceNumber = 0

        let inputNode = engine.inputNode

        // Use nil format — iOS delivers in hardware native format.
        // We convert lazily in the callback when the first valid buffer arrives.
        // This avoids crashes when the hardware can't satisfy a specific format request.
        converter = nil

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) {
            [weak self] buffer, _ in
            guard let self else { return }

            self.updateInputLevelFromRawBuffer(buffer)

            let bufFormat = buffer.format
            guard bufFormat.sampleRate > 0, buffer.frameLength > 0 else { return }

            // Create converter lazily on first valid buffer
            if self.converter == nil && (bufFormat.sampleRate != Constants.Opus.sampleRate || bufFormat.channelCount != 1 || bufFormat.commonFormat != .pcmFormatInt16) {
                self.converter = AVAudioConverter(from: bufFormat, to: self.targetFormat)
                Logger.audio.info("Converter: \(bufFormat.sampleRate)Hz/\(bufFormat.channelCount)ch -> 16000Hz/1ch/Int16")
            }
            self.processInputBuffer(buffer)
        }

        Logger.audio.info("Capture started")
    }

    func stopCapture() {
        guard let engine, isCapturing else { return }

        engine.inputNode.removeTap(onBus: 0)
        isCapturing = false
        captureAccumulator.removeAll()
        converter = nil

        Logger.audio.info("Capture stopped")
    }

    func receiveAudioPacket(_ opusData: Data, sequenceNumber: UInt32) {
        guard let codec, let jitterBuffer else { return }

        do {
            let pcmBuffer = try codec.decode(opusData)
            jitterBuffer.push(pcmBuffer: pcmBuffer, sequenceNumber: sequenceNumber)
        } catch {
            Logger.audio.error("Failed to decode audio packet seq=\(sequenceNumber): \(error.localizedDescription)")
            // Attempt PLC
            do {
                let plcBuffer = try codec.decodePLC()
                jitterBuffer.push(pcmBuffer: plcBuffer, sequenceNumber: sequenceNumber)
            } catch {
                Logger.audio.error("PLC failed: \(error.localizedDescription)")
            }
        }
    }

    func teardown() {
        stopCapture()

        engine?.stop()
        if let node = sourceNode {
            engine?.detach(node)
        }
        sourceNode = nil
        engine = nil
        codec = nil

        jitterBuffer?.reset()
        jitterBuffer = nil

        AudioSessionManager.deactivate()
        Logger.audio.info("AudioEngine torn down")
    }

    // MARK: - Private

    private func processInputBuffer(_ buffer: AVAudioPCMBuffer) {
        let pcmBuffer: AVAudioPCMBuffer

        if let converter {
            // Downsample to target format
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: AVAudioFrameCount(samplesPerFrame * 2)
            ) else { return }

            var error: NSError?
            nonisolated(unsafe) var hasData = true
            nonisolated(unsafe) let inputBuffer = buffer
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                if hasData {
                    outStatus.pointee = .haveData
                    hasData = false
                    return inputBuffer
                }
                outStatus.pointee = .noDataNow
                return nil
            }

            let status = converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
            guard status != .error, error == nil else {
                Logger.audio.error("Conversion failed: \(error?.localizedDescription ?? "unknown")")
                return
            }
            pcmBuffer = convertedBuffer
        } else {
            pcmBuffer = buffer
        }

        // Extract Int16 samples
        guard let channelData = pcmBuffer.int16ChannelData else { return }
        let frameLength = Int(pcmBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

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
