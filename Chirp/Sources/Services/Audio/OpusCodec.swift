import AVFoundation
import Opus
import OSLog

final class OpusCodec: Sendable {
    private let encoder: Opus.Encoder
    private let decoder: Opus.Decoder
    private let sampleRate: Int32
    private let channels: Int32
    private let samplesPerFrame: Int

    init() throws {
        self.sampleRate = Int32(Constants.Opus.sampleRate)
        self.channels = Int32(Constants.Opus.channels)
        self.samplesPerFrame = Constants.Opus.samplesPerFrame

        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Constants.Opus.sampleRate,
            channels: AVAudioChannelCount(channels),
            interleaved: true
        )!

        self.encoder = try Opus.Encoder(format: format, application: .voip)
        try self.encoder.configureBitrate(Constants.Opus.bitrate)

        self.decoder = try Opus.Decoder(format: format)

        Logger.audio.info("OpusCodec initialized: \(self.sampleRate)Hz, \(self.channels)ch, \(self.samplesPerFrame) samples/frame")
    }

    func encode(_ pcmBuffer: AVAudioPCMBuffer) throws -> Data {
        return try encoder.encode(pcmBuffer)
    }

    func decode(_ opusData: Data) throws -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(sampleRate),
            channels: AVAudioChannelCount(channels),
            interleaved: true
        )!

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samplesPerFrame)
        ) else {
            throw OpusCodecError.bufferAllocationFailed
        }

        try decoder.decode(opusData, to: outputBuffer)
        return outputBuffer
    }

    func decodePLC() throws -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(sampleRate),
            channels: AVAudioChannelCount(channels),
            interleaved: true
        )!

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samplesPerFrame)
        ) else {
            throw OpusCodecError.bufferAllocationFailed
        }

        // PLC: pass nil data to decoder to generate concealment frame
        try decoder.decode(nil, to: outputBuffer)
        return outputBuffer
    }
}

enum OpusCodecError: Error, Sendable {
    case bufferAllocationFailed
    case encodeFailed
    case decodeFailed
}
