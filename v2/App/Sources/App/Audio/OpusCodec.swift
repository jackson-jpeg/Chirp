@preconcurrency import AVFoundation
@preconcurrency import Opus

/// Opus at 16 kHz mono, 20 ms frames: the voice format on the wire.
///
/// Carried over from 1.0 (`Services/Audio/OpusCodec.swift`), trimmed to what
/// 2.0 uses: the encoder through the C shim (so FEC and the bitrate can be
/// set), the decoder through swift-opus, and packet loss concealment. 1.0's
/// adaptive bitrate had no caller (audit section 7) and is gone.
///
/// Not thread-safe: the encoder belongs to the capture queue and the decoder
/// to the playback queue (`VoiceEngine` makes one codec for each).
final class OpusCodec: @unchecked Sendable {
    static let sampleRate: Double = 16_000
    static let samplesPerFrame = 320   // 20 ms
    static let bitrate: Int32 = 16_000
    /// Assumed loss on a phone-to-phone line, so FEC carries some redundancy.
    static let expectedLossPercent: Int32 = 10

    /// 16-bit interleaved mono, the format both sides of the codec use.
    static let pcmFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate,
                                         channels: 1, interleaved: true)!

    enum Failure: Error { case encoder, encode, buffer }

    private let encoder: ChirpOpusEncoder
    private let decoder: Opus.Decoder

    init() throws {
        // 2048 = OPUS_APPLICATION_VOIP
        guard let enc = chirp_opus_encoder_create(Int32(Self.sampleRate), 1, 2048) else { throw Failure.encoder }
        chirp_opus_set_bitrate(enc, Self.bitrate)
        chirp_opus_set_inband_fec(enc, 1)
        chirp_opus_set_packet_loss_perc(enc, Self.expectedLossPercent)
        encoder = enc
        decoder = try Opus.Decoder(format: Self.pcmFormat, application: .voip)
    }

    deinit { chirp_opus_encoder_destroy(encoder) }

    /// One frame of `samplesPerFrame` samples to one Opus packet.
    func encode(_ samples: UnsafeBufferPointer<Int16>) throws -> Data {
        var output = [UInt8](repeating: 0, count: 1500)
        let n = chirp_opus_encode(encoder, samples.baseAddress, Int32(samples.count), &output, Int32(output.count))
        guard n > 0 else { throw Failure.encode }
        return Data(output.prefix(Int(n)))
    }

    /// One Opus packet to 16-bit PCM bytes.
    func decode(_ packet: Data) throws -> Data {
        Self.bytes(of: try decoder.decode(packet))
    }

    /// A concealment frame for one lost packet.
    func conceal() throws -> Data {
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.pcmFormat,
                                         frameCapacity: AVAudioFrameCount(Self.samplesPerFrame)) else { throw Failure.buffer }
        try decoder.decode(UnsafeBufferPointer<UInt8>(start: nil, count: 0), to: out)
        return Self.bytes(of: out)
    }

    private static func bytes(of buffer: AVAudioPCMBuffer) -> Data {
        guard let ch = buffer.int16ChannelData else { return Data() }
        return Data(bytes: ch[0], count: Int(buffer.frameLength) * MemoryLayout<Int16>.size)
    }
}
