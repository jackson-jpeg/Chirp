import Foundation
import Observation
import OSLog

// MARK: - MeshShield

/// Traffic-analysis resistance. Not a feature — infrastructure.
///
/// What it does, precisely:
/// 1. **Cover traffic**: Continuously injects encrypted packets indistinguishable
///    from real messages. Random origin IDs, packet types, TTLs, payload sizes.
/// 2. Every node relays everything, so an observer capturing traffic cannot tell
///    who is communicating or which packets are real.
///
/// What it does NOT do: message confidentiality lives in ``ChannelCrypto`` —
/// AES-GCM-256 under the shared channel key. That is the app's one encryption
/// layer, and it is exactly what the UI tells the user: messages are encrypted
/// between channel members. There is no ephemeral-DH layer and no per-message
/// signature; an earlier design claimed both without delivering either, and the
/// code was removed rather than left as a false promise.
@Observable
@MainActor
final class MeshShield {

    private let logger = Logger(subsystem: Constants.subsystem, category: "MeshShield")

    /// Internal magic that marks cover traffic payloads. After encryption, invisible on the wire.
    static let coverMagic: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF]

    private var multipeerTransport: MultipeerTransport?
    private var fakeTrafficTask: Task<Void, Never>?

    /// Returns the ChannelCrypto for a given channel ID, if the channel is locked.
    var channelCryptoProvider: ((String) -> ChannelCrypto?)?

    /// Returns the current active channel ID, if any.
    var activeChannelProvider: (() -> String?)?

    /// Returns the number of visible peers (for adaptive rate limiting).
    var peerCountProvider: (() -> Int)?

    // MARK: - Token Bucket Rate Limiter

    /// Maximum tokens (burst capacity).
    private let maxTokens: Double = 5.0
    /// Token refill rate: 20 per minute = 1 per 3 seconds.
    private let refillRate: Double = 20.0 / 60.0
    /// Current token count.
    private var tokens: Double = 5.0
    /// Last time tokens were refilled.
    private var lastRefill: Date = Date()

    // MARK: - Init

    init() {}

    // MARK: - Lifecycle

    /// Wire the transport and start cover traffic. Called once from AppState.start().
    func start(transport: MultipeerTransport) {
        self.multipeerTransport = transport
        startCoverTraffic()
        logger.info("MeshShield active")
    }

    func stop() {
        fakeTrafficTask?.cancel()
        fakeTrafficTask = nil
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

    /// Refill tokens based on elapsed time and consume one if available.
    private func consumeToken() -> Bool {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefill)
        lastRefill = now

        // Adaptive rate: halve refill when >10 peers (they're also generating cover)
        let peerCount = peerCountProvider?() ?? 0
        let adjustedRate = peerCount > 10 ? refillRate / 2.0 : refillRate

        tokens = min(maxTokens, tokens + elapsed * adjustedRate)
        guard tokens >= 1.0 else { return false }
        tokens -= 1.0
        return true
    }

    private func injectCoverPacket() {
        // Skip if no active channel (unencrypted cover is pointless)
        guard let activeID = activeChannelProvider?(),
              let crypto = channelCryptoProvider?(activeID) else {
            return
        }

        // Rate limit
        guard consumeToken() else {
            logger.trace("Cover traffic rate-limited, skipping injection")
            return
        }

        let packetType: MeshPacket.PacketType = Bool.random() ? .audio : .control
        let payloadSize = packetType == .audio ? Int.random(in: 80...350) : Int.random(in: 80...600)

        var coverPayload = Data(Self.coverMagic)
        var noise = [UInt8](repeating: 0, count: max(0, payloadSize - 4))
        for i in noise.indices { noise[i] = UInt8.random(in: 0...255) }
        coverPayload.append(Data(noise))

        let wirePayload: Data
        do {
            wirePayload = try crypto.encrypt(coverPayload)
        } catch {
            logger.error("Cover traffic encryption failed, skipping: \(error.localizedDescription)")
            return
        }

        let packet = MeshPacket(
            type: packetType,
            ttl: UInt8.random(in: 1...6),
            originID: UUID(),
            packetID: UUID(),
            sequenceNumber: UInt32.random(in: 0...UInt32.max),
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            channelID: activeID,
            payload: wirePayload
        )

        multipeerTransport?.forwardPacket(packet.serialize(), excludePeer: "")
    }
}
