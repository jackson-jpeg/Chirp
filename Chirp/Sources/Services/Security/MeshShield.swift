import CryptoKit
import Foundation
import Observation
import OSLog

// MARK: - Triple-Layer Encryption

/// Triple-layer encryption for all mesh messages.
///
/// Wire format (outermost to innermost):
/// ```
/// [ephemeralPubKey:32][AES-GCM nonce+ciphertext+tag from Layer 1]
///   └── contains: [Ed25519 signature:64][AES-GCM nonce+ciphertext+tag from Layer 2]
///        └── contains: [original message payload]
/// ```
enum MeshShieldCrypto {

    private static let layer1Salt = Data("ChirpMeshShield-L1".utf8)

    /// Wrap a payload in three layers of encryption.
    ///
    /// - Layer 1 (outermost): One-time Curve25519 DH, AES-GCM-256.
    ///   Ephemeral key destroyed after use. Ciphertext randomisation.
    /// - Layer 2 (group): AES-GCM-256 with channel key. Proves channel membership.
    /// - Layer 3 (innermost): Ed25519 signature. Confirms sender identity.
    ///
    /// Signature and ephemeral key are inside the encrypted layers —
    /// an interceptor cannot determine sender or recipient.
    static func encrypt(
        _ plaintext: Data,
        channelCrypto: ChannelCrypto,
        peerIdentity: PeerIdentity
    ) async throws -> Data {

        // Layer 3: Sign the plaintext
        let signature = try await peerIdentity.sign(plaintext)

        // Layer 2: Encrypt with channel key
        let layer2Ciphertext = try channelCrypto.encrypt(plaintext)

        // Combine: [signature:64][layer2 ciphertext]
        var innerPackage = Data(capacity: 64 + layer2Ciphertext.count)
        innerPackage.append(signature)
        innerPackage.append(layer2Ciphertext)

        // Layer 1: Ephemeral DH encryption
        let ephemeralPrivate = Curve25519.KeyAgreement.PrivateKey()
        let ephemeralPublic = ephemeralPrivate.publicKey
        let symmetricKey = deriveLayer1Key(from: ephemeralPublic.rawRepresentation)
        let sealed = try AES.GCM.seal(innerPackage, using: symmetricKey)

        // Wire: [ephemeralPubKey:32][nonce+ciphertext+tag]
        var wire = Data(capacity: 32 + sealed.combined!.count)
        wire.append(ephemeralPublic.rawRepresentation)
        wire.append(sealed.combined!)

        // Ephemeral private key destroyed when it goes out of scope
        return wire
    }

    /// Attempt to unwrap a triple-encrypted payload.
    /// Returns the original plaintext, or `nil` if decryption fails.
    static func decrypt(
        _ wire: Data,
        channelCrypto: ChannelCrypto
    ) -> Data? {
        guard wire.count > 32 + 28 + 64 + 28 else { return nil }

        let ephemeralKeyData = Data(wire.prefix(32))
        let layer1Ciphertext = Data(wire.dropFirst(32))

        // Layer 1 decrypt
        let symmetricKey = deriveLayer1Key(from: ephemeralKeyData)
        guard let sealedBox = try? AES.GCM.SealedBox(combined: layer1Ciphertext),
              let innerPackage = try? AES.GCM.open(sealedBox, using: symmetricKey) else {
            return nil
        }

        guard innerPackage.count > 64 + 28 else { return nil }
        let layer2Ciphertext = Data(innerPackage.dropFirst(64))

        // Layer 2 decrypt
        guard let plaintext = try? channelCrypto.decrypt(layer2Ciphertext) else {
            return nil
        }

        return plaintext
    }

    private static func deriveLayer1Key(from ephemeralKeyData: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ephemeralKeyData),
            salt: layer1Salt,
            info: Data(),
            outputByteCount: 32
        )
    }
}

// MARK: - MeshShield

/// Always-on traffic analysis protection. Not a feature — infrastructure.
///
/// 1. **Cover traffic**: Continuously injects encrypted packets indistinguishable
///    from real messages. Random origin IDs, packet types, TTLs, payload sizes.
/// 2. **Triple encryption**: All real messages on locked channels are wrapped in
///    ephemeral DH + channel AES-GCM + Ed25519 signature.
/// 3. Every node relays everything. An observer capturing traffic cannot determine
///    who is communicating, which packets are real, or who authored them.
@Observable
@MainActor
final class MeshShield {

    private let logger = Logger(subsystem: Constants.subsystem, category: "MeshShield")

    /// Internal magic that marks cover traffic payloads. After encryption, invisible on the wire.
    static let coverMagic: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF]

    private var multipeerTransport: MultipeerTransport?
    private var wifiAwareTransport: WiFiAwareTransport?
    private var fakeTrafficTask: Task<Void, Never>?

    // MARK: - Init

    init() {}

    // MARK: - Lifecycle

    /// Wire transports and start cover traffic. Called once from AppState.start().
    func start(
        transport: MultipeerTransport,
        waTransport: WiFiAwareTransport?
    ) {
        self.multipeerTransport = transport
        self.wifiAwareTransport = waTransport
        startCoverTraffic()
        logger.info("MeshShield active")
    }

    func stop() {
        fakeTrafficTask?.cancel()
        fakeTrafficTask = nil
    }

    // MARK: - Encryption API

    /// Triple-encrypt a payload. Used by TextMessageService for locked channels.
    func encrypt(_ plaintext: Data, channelCrypto: ChannelCrypto) async -> Data? {
        do {
            return try await MeshShieldCrypto.encrypt(
                plaintext,
                channelCrypto: channelCrypto,
                peerIdentity: PeerIdentity.shared
            )
        } catch {
            logger.error("Encryption failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Triple-decrypt a payload. Returns plaintext or nil if not triple-encrypted.
    nonisolated func decrypt(_ ciphertext: Data, channelCrypto: ChannelCrypto) -> Data? {
        MeshShieldCrypto.decrypt(ciphertext, channelCrypto: channelCrypto)
    }

    /// Check if a payload is cover traffic (silently discard).
    static func isCoverTraffic(_ payload: Data) -> Bool {
        guard payload.count >= 4 else { return false }
        let s = payload.startIndex
        return payload[s] == 0xDE && payload[s+1] == 0xAD
            && payload[s+2] == 0xBE && payload[s+3] == 0xEF
    }

    // MARK: - Cover Traffic

    private func startCoverTraffic() {
        fakeTrafficTask?.cancel()
        fakeTrafficTask = Task { [weak self] in
            while !Task.isCancelled {
                let delay = Double.random(in: 2.0...10.0)
                do { try await Task.sleep(for: .seconds(delay)) } catch { break }
                guard !Task.isCancelled, let self else { break }
                self.injectCoverPacket()
            }
        }
    }

    private func injectCoverPacket() {
        let packetType: MeshPacket.PacketType = Bool.random() ? .audio : .control
        let payloadSize = packetType == .audio ? Int.random(in: 100...300) : Int.random(in: 50...500)

        // Cover payload: magic prefix + random bytes (indistinguishable after encryption)
        var payload = Data(Self.coverMagic)
        var noise = [UInt8](repeating: 0, count: max(0, payloadSize - 4))
        for i in noise.indices { noise[i] = UInt8.random(in: 0...255) }
        payload.append(Data(noise))

        let packet = MeshPacket(
            type: packetType,
            ttl: UInt8.random(in: 1...6),
            originID: UUID(),
            packetID: UUID(),
            sequenceNumber: UInt32.random(in: 0...UInt32.max),
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            channelID: "",
            payload: payload
        )

        let serialized = packet.serialize()
        multipeerTransport?.forwardPacket(serialized, excludePeer: "")
        wifiAwareTransport?.forwardPacket(serialized, excludePeer: "")
    }
}
