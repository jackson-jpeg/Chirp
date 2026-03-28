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

        // CRITICAL: Access inputNode BEFORE engine.start() to force the audio
        // graph to include the input. Without this, inputNode.outputFormat
        // returns 0Hz on real devices.
        let _ = engine.inputNode

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

        // Get the input node's REAL hardware format AFTER engine is running.
        // We accessed inputNode during setup() to force initialization.
        let hwFormat = inputNode.outputFormat(forBus: 0)
        Logger.audio.info("Input hw format: \(hwFormat.sampleRate)Hz/\(hwFormat.channelCount)ch/\(hwFormat.commonFormat.rawValue)")

        // Determine tap format: use hardware format if valid, otherwise
        // create a format using the audio session's actual sample rate.
        let tapFormat: AVAudioFormat
        if hwFormat.sampleRate > 0 {
            tapFormat = hwFormat
        } else {
            // Fallback: use the audio session's sample rate (always valid)
            let sessionRate = AVAudioSession.sharedInstance().sampleRate
            tapFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sessionRate > 0 ? sessionRate : 48000,
                channels: 1,
                interleaved: false
            )!
            Logger.audio.info("Using session rate fallback: \(tapFormat.sampleRate)Hz")
        }

        // Create converter from tap format to our 16kHz mono Int16 target
        if tapFormat.sampleRate != Constants.Opus.sampleRate
            || tapFormat.channelCount != 1
            || tapFormat.commonFormat != .pcmFormatInt16 {
            converter = AVAudioConverter(from: tapFormat, to: targetFormat)
            Logger.audio.info("Converter: \(tapFormat.sampleRate)Hz/\(tapFormat.channelCount)ch -> 16000Hz/1ch/Int16")
        } else {
            converter = nil
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) {
            [weak self] buffer, _ in
            guard let self, self.isCapturing else { return }
            guard buffer.frameLength > 0 else { return }

            self.updateInputLevelFromRawBuffer(buffer)
            self.processInputBuffer(buffer)
        }

        Logger.audio.info("Capture started — tap: \(tapFormat.sampleRate)Hz/\(tapFormat.channelCount)ch")
    }

    func stopCapture() {
        guard let engine, isCapturing else { return }

        // Set flag FIRST so the tap callback exits quickly
        isCapturing = false
        // Clear converter BEFORE removing tap to avoid deadlock
        converter = nil
        engine.inputNode.removeTap(onBus: 0)
        captureAccumulator.removeAll()

        Logger.audio.info("Capture stopped")
    }

    func receiveAudioPacket(_ opusData: Data, sequenceNumber: UInt32) {
        guard let codec, let jitterBuffer else {
            Logger.audio.warning("receiveAudioPacket: codec or jitterBuffer nil")
            return
        }

        do {
            let pcmBuffer = try codec.decode(opusData)
            jitterBuffer.push(pcmBuffer: pcmBuffer, sequenceNumber: sequenceNumber)
            if sequenceNumber % 50 == 0 {
                Logger.audio.info("Audio flowing: seq=\(sequenceNumber), decoded \(pcmBuffer.frameLength) frames, jb=\(jitterBuffer.bufferedCount) buffered")
            }
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
