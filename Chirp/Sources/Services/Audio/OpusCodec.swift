import AVFoundation
@preconcurrency import Opus
import OSLog

final class OpusCodec: @unchecked Sendable {
    /// C-level encoder via shim (supports bitrate control via opus_encoder_ctl).
    private let encoder: ChirpOpusEncoder
    /// Swift-wrapper decoder (no CTL needed for decode).
    private let decoder: Opus.Decoder
    private let samplesPerFrame: Int

    /// Current encoder bitrate in bits per second.
    private(set) var currentBitrate: Int = Constants.Opus.bitrate

    /// Whether in-band Forward Error Correction is enabled.
    private(set) var fecEnabled: Bool = false

    /// Expected packet loss percentage (0-100) used by FEC to tune redundancy.
    private(set) var expectedPacketLossPercent: Int = 0

    let format: AVAudioFormat

    // MARK: - Adaptive Bitrate

    /// Minimum Opus bitrate (narrowband voice floor).
    static let minBitrate: Int = 6_000
    /// Maximum Opus bitrate.
    static let maxBitrate: Int = 510_000

    /// Quality tiers based on available link throughput.
    enum BitrateQuality: Int, CaseIterable, Sendable {
        case excellent = 24_000  // >100 kbps available
        case good      = 16_000  // >50 kbps
        case fair      = 12_000  // >20 kbps
        case poor      =  8_000  // <20 kbps

        /// Choose quality tier from available bandwidth in bits per second.
        static func from(availableBandwidth bps: Int) -> BitrateQuality {
            switch bps {
            case 100_000...:  return .excellent
            case  50_000...:  return .good
            case  20_000...:  return .fair
            default:          return .poor
            }
        }
    }

    init() throws {
        self.samplesPerFrame = Constants.Opus.samplesPerFrame

        let fmt = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Constants.Opus.sampleRate,
            channels: AVAudioChannelCount(Constants.Opus.channels),
            interleaved: true
        )!
        self.format = fmt

        // Create encoder via C shim (application: 2048 = OPUS_APPLICATION_VOIP)
        guard let enc = chirp_opus_encoder_create(
            Int32(Constants.Opus.sampleRate),
            Int32(Constants.Opus.channels),
            2048
        ) else {
            throw OpusCodecError.encodeFailed
        }
        self.encoder = enc

        // Set initial bitrate
        chirp_opus_set_bitrate(enc, Int32(Constants.Opus.bitrate))
        self.currentBitrate = Constants.Opus.bitrate

        // Enable in-band FEC for packet loss recovery (~2kbps overhead)
        chirp_opus_set_inband_fec(enc, 1)
        self.fecEnabled = true
        // Assume 10% loss as a reasonable default for BLE mesh
        chirp_opus_set_packet_loss_perc(enc, 10)
        self.expectedPacketLossPercent = 10

        // Decoder uses the Swift wrapper (no CTL needed)
        self.decoder = try Opus.Decoder(format: fmt, application: .voip)

        Logger.audio.info("OpusCodec initialized: \(Constants.Opus.sampleRate)Hz, \(Constants.Opus.channels)ch, \(Constants.Opus.bitrate)bps, FEC enabled")
    }

    deinit {
        chirp_opus_encoder_destroy(encoder)
    }

    /// Dynamically adjust the Opus encoder bitrate.
    /// The value is clamped to Opus's valid range (6000-510000 bps).
    func setTargetBitrate(_ bitsPerSecond: Int) {
        let clamped = max(Self.minBitrate, min(Self.maxBitrate, bitsPerSecond))
        guard clamped != currentBitrate else { return }
        let result = chirp_opus_set_bitrate(encoder, Int32(clamped))
        if result == 0 {
            currentBitrate = clamped
            Logger.audio.info("Opus bitrate changed to \(clamped) bps")
        } else {
            Logger.audio.error("Failed to set Opus bitrate to \(clamped): error \(result)")
        }
    }

    /// Enable or disable in-band Forward Error Correction.
    func setFEC(enabled: Bool) {
        let result = chirp_opus_set_inband_fec(encoder, enabled ? 1 : 0)
        if result == 0 {
            fecEnabled = enabled
            Logger.audio.info("Opus FEC \(enabled ? "enabled" : "disabled")")
        } else {
            Logger.audio.error("Failed to set Opus FEC: error \(result)")
        }
    }

    /// Set expected packet loss percentage (0-100) to tune FEC redundancy.
    func setExpectedPacketLoss(_ percent: Int) {
        let clamped = max(0, min(100, percent))
        let result = chirp_opus_set_packet_loss_perc(encoder, Int32(clamped))
        if result == 0 {
            expectedPacketLossPercent = clamped
            Logger.audio.info("Opus expected packet loss set to \(clamped)%")
        } else {
            Logger.audio.error("Failed to set Opus packet loss: error \(result)")
        }
    }

    /// Encode a PCM buffer into Opus data
    func encode(_ pcmBuffer: AVAudioPCMBuffer) throws -> Data {
        guard let int16Data = pcmBuffer.int16ChannelData else {
            throw OpusCodecError.encodeFailed
        }

        var output = [UInt8](repeating: 0, count: 4000)
        let encodedBytes = chirp_opus_encode(
            encoder,
            int16Data[0],
            Int32(pcmBuffer.frameLength),
            &output,
            Int32(output.count)
        )

        if encodedBytes < 0 {
            throw OpusCodecError.encodeFailed
        }
        return Data(output.prefix(Int(encodedBytes)))
    }

    /// Decode Opus data into a PCM buffer
    func decode(_ opusData: Data) throws -> AVAudioPCMBuffer {
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
