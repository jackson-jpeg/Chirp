import AVFoundation
@preconcurrency import Opus
import OSLog

final class OpusCodec: @unchecked Sendable {
    private let encoder: Opus.Encoder
    private let decoder: Opus.Decoder
    private let samplesPerFrame: Int

    let format: AVAudioFormat

    init() throws {
        self.samplesPerFrame = Constants.Opus.samplesPerFrame

        let fmt = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Constants.Opus.sampleRate,
            channels: AVAudioChannelCount(Constants.Opus.channels),
            interleaved: true
        )!
        self.format = fmt

        self.encoder = try Opus.Encoder(format: fmt, application: .voip)
        self.decoder = try Opus.Decoder(format: fmt, application: .voip)

        Logger.audio.info("OpusCodec initialized: \(Constants.Opus.sampleRate)Hz, \(Constants.Opus.channels)ch")
    }

    /// Encode a PCM buffer into Opus data
    func encode(_ pcmBuffer: AVAudioPCMBuffer) throws -> Data {
        // swift-opus encode API: encode(buffer, to: &data) -> Int
        var output = Data(count: 4000) // max opus packet size
        let encodedBytes = try encoder.encode(pcmBuffer, to: &output)
        return Data(output.prefix(encodedBytes))
    }

    /// Decode Opus data into a PCM buffer
    func decode(_ opusData: Data) throws -> AVAudioPCMBuffer {
        // swift-opus decode API: decode(Data) -> AVAudioPCMBuffer
        return try decoder.decode(opusData)
    }

    /// Generate a PLC (packet loss concealment) frame
    func decodePLC() throws -> AVAudioPCMBuffer {
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samplesPerFrame)
        ) else {
            throw OpusCodecError.bufferAllocationFailed
        }

        // Pass empty data to trigger PLC
        let emptyInput = UnsafeBufferPointer<UInt8>(start: nil, count: 0)
        try decoder.decode(emptyInput, to: outputBuffer)
        return outputBuffer
    }
}

enum OpusCodecError: Error, Sendable {
    case bufferAllocationFailed
    case encodeFailed
    case decodeFailed
}
