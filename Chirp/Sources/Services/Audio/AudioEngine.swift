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

        // Playback source node: pulls decoded PCM from jitter buffer
        let jb = jitterBuffer
        let playbackFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Constants.Opus.sampleRate,
            channels: 1,
            interleaved: true
        )!

        let node = AVAudioSourceNode(format: playbackFormat) { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let requestedBytes = Int(frameCount) * MemoryLayout<Int16>.size

            if let data = jb.pull(frameCount: 1) {
                for bufferIndex in 0 ..< ablPointer.count {
                    let buffer = ablPointer[bufferIndex]
                    guard let dest = buffer.mData else { continue }
                    let bytesToCopy = min(data.count, requestedBytes)
                    data.withUnsafeBytes { src in
                        dest.copyMemory(from: src.baseAddress!, byteCount: bytesToCopy)
                    }
                    // Zero-fill remainder if needed
                    if bytesToCopy < requestedBytes {
                        dest.advanced(by: bytesToCopy)
                            .initializeMemory(as: UInt8.self, repeating: 0, count: requestedBytes - bytesToCopy)
                    }
                }
            } else {
                // Silence when no data available
                for bufferIndex in 0 ..< ablPointer.count {
                    let buffer = ablPointer[bufferIndex]
                    guard let dest = buffer.mData else { continue }
                    memset(dest, 0, requestedBytes)
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
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Set up converter if input sample rate differs from target
        if inputFormat.sampleRate != Constants.Opus.sampleRate || inputFormat.channelCount != 1 {
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
            Logger.audio.info(
                "Converter created: \(inputFormat.sampleRate)Hz/\(inputFormat.channelCount)ch -> \(Constants.Opus.sampleRate)Hz/1ch"
            )
        } else {
            converter = nil
        }

        inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(samplesPerFrame), format: inputFormat) {
            [weak self] buffer, _ in
            self?.processInputBuffer(buffer)
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
            var hasData = true
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                if hasData {
                    outStatus.pointee = .haveData
                    hasData = false
                    return buffer
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
                let seq = sequenceNumber
                sequenceNumber += 1
                onEncodedAudio?(encodedData)
                Logger.audio.debug("Encoded frame seq=\(seq), \(encodedData.count) bytes")
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
        inputLevel = rms
    }
}
