import CryptoKit
import Foundation
import Observation
import OSLog
import UIKit

/// Orchestrates CICADA steganographic communication.
///
/// Manages encoding/decoding of hidden messages within normal chat text,
/// key derivation from channel encryption keys, and hidden content storage.
@Observable
@MainActor
final class CICADAService {

    private let logger = Logger(subsystem: Constants.subsystem, category: "CICADA")

    // MARK: - Public State

    /// Whether CICADA steganography is enabled.
    var isEnabled: Bool = UserDefaults.standard.bool(forKey: Keys.enabled) {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.enabled) }
    }

    /// Decoded hidden messages keyed by MeshTextMessage ID.
    /// Ephemeral — cleared each session for security.
    private(set) var hiddenMessages: [UUID: String] = [:]

    // MARK: - Dependencies

    /// Provides channel crypto for key derivation. Set by AppState.
    var channelCryptoProvider: ((String) -> ChannelCrypto?)?

    // MARK: - Private

    private enum Keys {
        static let enabled = "com.chirpchirp.cicada.enabled"
    }

    // MARK: - Text Stego

    /// Encode a hidden message into cover text for a specific channel.
    /// Returns the stego-encoded text, or nil if encoding fails (not enough capacity, no channel key).
    func encodeText(cover: String, hidden: String, channelID: String) -> String? {
        guard isEnabled, !hidden.isEmpty else { return nil }
        guard let key = cicadaKey(for: channelID) else {
            logger.warning("No CICADA key available for channel \(channelID)")
            return nil
        }
        let hiddenData = Data(hidden.utf8)
        guard let encoded = TextStego.encode(cover: cover, hidden: hiddenData, key: key) else {
            logger.warning("CICADA encode failed — insufficient capacity (\(cover.count) chars, \(hiddenData.count) bytes)")
            return nil
        }
        logger.info("CICADA encoded \(hiddenData.count) bytes into \(cover.count)-char cover")
        return encoded
    }

    /// Decode hidden content from a received message.
    /// Stores result in hiddenMessages if found.
    func decodeAndStore(message: MeshTextMessage, channelID: String) {
        guard isEnabled else { return }
        guard TextStego.hasHiddenContent(message.text) else { return }
        guard let key = cicadaKey(for: channelID) else { return }

        if let data = TextStego.decode(message.text, key: key),
           let text = String(data: data, encoding: .utf8) {
            hiddenMessages[message.id] = text
            logger.info("CICADA decoded hidden message in \(message.id)")
        }
    }

    /// Check if a message has hidden content (quick check, no decryption).
    func hasHiddenContent(_ text: String) -> Bool {
        guard isEnabled else { return false }
        return TextStego.hasHiddenContent(text)
    }

    /// Get the hidden message for a specific message ID.
    func hiddenText(for messageID: UUID) -> String? {
        hiddenMessages[messageID]
    }

    /// Calculate capacity for a cover text on a channel.
    func capacity(coverLength: Int) -> Int {
        TextStego.capacity(coverLength: coverLength)
    }

    // MARK: - Image Stego

    /// Encode hidden data into an image, returning PNG data.
    func encodeImage(_ image: UIImage, hidden: String, channelID: String) -> Data? {
        guard isEnabled, !hidden.isEmpty else { return nil }
        guard let key = cicadaKey(for: channelID) else { return nil }
        let hiddenData = Data(hidden.utf8)
        return ImageStego.encode(image: image, hidden: hiddenData, key: key)
    }

    /// Decode hidden data from PNG image data.
    func decodeImage(pngData: Data, channelID: String) -> String? {
        guard isEnabled, ImageStego.isPNG(pngData) else { return nil }
        guard let key = cicadaKey(for: channelID) else { return nil }
        guard let data = ImageStego.decode(pngData: pngData, key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Audio Stego

    /// Create a timing schedule for encoding hidden data in audio packet timing.
    func createAudioSchedule(hidden: String, channelID: String) -> AudioStego.TimingSchedule? {
        guard isEnabled, !hidden.isEmpty else { return nil }
        guard let key = cicadaKey(for: channelID) else { return nil }
        return AudioStego.TimingSchedule(hidden: Data(hidden.utf8), key: key)
    }

    /// Create a timing decoder for extracting hidden data from audio packet timing.
    func createAudioDecoder(channelID: String) -> AudioStego.TimingDecoder? {
        guard isEnabled else { return nil }
        guard let key = cicadaKey(for: channelID) else { return nil }
        return AudioStego.TimingDecoder(key: key)
    }

    // MARK: - Key Derivation

    private func cicadaKey(for channelID: String) -> SymmetricKey? {
        guard let crypto = channelCryptoProvider?(channelID) else { return nil }
        return crypto.deriveSubkey(salt: Constants.CICADA.keySalt, info: Data(channelID.utf8))
    }
}
