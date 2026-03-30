import Foundation
import OSLog

/// Manages the creation, relay-storage, and retrieval of location-anchored
/// encrypted dead-drop messages on the ChirpChirp mesh network.
///
/// Dead drops are encrypted with a key derived from the precise geohash of their
/// physical location — only a peer standing in the same ~153 m cell (or one of
/// its 8 neighbors) can decrypt the payload.
@Observable
@MainActor
final class DeadDropService {

    private let logger = Logger(subsystem: Constants.subsystem, category: "DeadDrop")

    // MARK: - Public state

    /// Drops we are holding as a relay node, keyed by drop ID.
    private(set) var storedDrops: [UUID: DeadDropMessage] = [:]

    /// Drops we created ourselves.
    private(set) var myDrops: [DeadDropMessage] = []

    /// Successfully decrypted messages, keyed by drop ID.
    private(set) var pickedUpMessages: [UUID: String] = [:]

    // MARK: - Callbacks

    /// Called when the service needs to broadcast a packet on a channel.
    /// Parameters: (packetData, channelID).
    var onSendPacket: ((Data, String) -> Void)?

    /// Location service used to obtain the current GPS position.
    var locationService: LocationService?

    // MARK: - Constants

    private static let maxStoredDrops = 100
    private static let defaultExpiryHours = 24

    // MARK: - Init

    init() {
        loadFromDisk()
    }

    // MARK: - Public API

    /// Create and broadcast a new dead-drop message.
    ///
    /// - Parameters:
    ///   - text: Plaintext message body.
    ///   - latitude: Drop latitude.
    ///   - longitude: Drop longitude.
    ///   - channelID: Mesh channel to broadcast on.
    ///   - senderID: Local peer ID.
    ///   - senderName: Display name of the sender.
    ///   - timeLockDate: Optional `YYYY-MM-DD` date; the drop cannot be opened before this day.
    ///   - expiryHours: Hours until the drop expires (default 24).
    ///   - nextHint: Optional chain hint for scavenger-hunt mode.
    func dropMessage(
        text: String,
        latitude: Double,
        longitude: Double,
        channelID: String,
        senderID: String,
        senderName: String,
        timeLockDate: String? = nil,
        expiryHours: Int = 24,
        nextHint: DropChainHint? = nil
    ) {
        let geohash = Geohash.encode(latitude: latitude, longitude: longitude, precision: 7)
        let prefix = String(geohash.prefix(4))

        // Build plaintext: message text, optionally followed by a chain hint.
        var plaintext: Data
        if let nextHint {
            // Encode hint as JSON appended after a null separator.
            var combined = Data(text.utf8)
            combined.append(0x00)
            if let hintJSON = try? MeshCodable.encoder.encode(nextHint) {
                combined.append(hintJSON)
            }
            plaintext = combined
        } else {
            plaintext = Data(text.utf8)
        }

        let isTimeLocked = timeLockDate != nil
        let dateForKey = isTimeLocked ? timeLockDate : nil

        guard let encrypted = try? DeadDropCrypto.seal(plaintext, geohash: geohash, date: dateForKey) else {
            logger.error("Failed to encrypt dead drop payload")
            return
        }

        let now = Date()
        let drop = DeadDropMessage(
            id: UUID(),
            senderID: senderID,
            senderName: senderName,
            encryptedPayload: encrypted,
            geohashPrefix: prefix,
            timestamp: now,
            expiresAt: now.addingTimeInterval(TimeInterval(expiryHours) * 3600),
            isTimeLocked: isTimeLocked,
            timeLockDate: timeLockDate,
            hasNextHint: nextHint != nil
        )

        myDrops.append(drop)
        saveToDisk()

        // Broadcast the drop on the mesh.
        do {
            let payload = try drop.wirePayload()
            onSendPacket?(payload, channelID)
            logger.info("Dropped message at geohash \(prefix, privacy: .public)*** (precision 7)")
        } catch {
            logger.error("Failed to encode dead drop wire payload: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Attempt to decrypt all stored drops using the device's current GPS position.
    ///
    /// For each drop we try the geohash at our exact position plus the 8
    /// neighboring cells. Time-locked drops additionally fold the current date
    /// into key derivation.
    func scanForDrops() {
        guard let location = locationService?.currentLocation else {
            logger.warning("Cannot scan for drops — no GPS fix")
            return
        }

        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let centerHash = Geohash.encode(latitude: lat, longitude: lon, precision: 7)
        let candidates = [centerHash] + Geohash.neighbors(of: centerHash)

        let todayString = Self.todayDateString()

        var decryptedCount = 0
        for (dropID, drop) in storedDrops {
            // Skip already-picked-up drops.
            guard pickedUpMessages[dropID] == nil else { continue }

            for candidate in candidates {
                let dateParam: String? = drop.isTimeLocked ? (drop.timeLockDate ?? todayString) : nil

                guard let plaintext = DeadDropCrypto.open(
                    drop.encryptedPayload,
                    geohash: candidate,
                    date: dateParam
                ) else { continue }

                // Successfully decrypted.
                let text = parsePlaintext(plaintext)
                pickedUpMessages[dropID] = text
                decryptedCount += 1
                logger.info("Picked up dead drop \(dropID.uuidString.prefix(8), privacy: .public) at geohash \(candidate.prefix(4), privacy: .public)")
                break
            }
        }

        if decryptedCount > 0 {
            saveToDisk()
            logger.info("Scan complete — picked up \(decryptedCount) drop(s)")
        } else {
            logger.debug("Scan complete — no drops within range")
        }
    }

    /// Handle an incoming mesh packet, dispatching `DRP!` and `DPK!` prefixes.
    func handlePacket(_ data: Data, channelID: String) {
        let drpPrefix = Data(DeadDropMessage.magicPrefix)
        let dpkPrefix = Data(DeadDropPickup.magicPrefix)

        if data.count > drpPrefix.count, data.prefix(drpPrefix.count) == drpPrefix {
            handleDropPacket(data)
        } else if data.count > dpkPrefix.count, data.prefix(dpkPrefix.count) == dpkPrefix {
            handlePickupPacket(data)
        }
    }

    /// Remove all expired drops from storage.
    func pruneExpired() {
        let now = Date()
        var prunedCount = 0

        for (id, drop) in storedDrops where drop.expiresAt < now {
            storedDrops.removeValue(forKey: id)
            prunedCount += 1
        }

        myDrops.removeAll { $0.expiresAt < now }

        if prunedCount > 0 {
            saveToDisk()
            logger.info("Pruned \(prunedCount) expired dead drop(s)")
        }
    }

    // MARK: - Packet handlers

    private func handleDropPacket(_ data: Data) {
        guard let drop = DeadDropMessage.from(payload: data) else {
            logger.warning("Failed to decode DRP! packet")
            return
        }

        // Only store if the drop's coarse area matches ours.
        guard shouldStore(drop) else {
            logger.debug("Ignoring drop outside our geohash area")
            return
        }

        guard storedDrops.count < Self.maxStoredDrops else {
            logger.warning("Drop storage full (\(Self.maxStoredDrops)) — ignoring new drop")
            return
        }

        guard storedDrops[drop.id] == nil else {
            logger.debug("Duplicate drop \(drop.id.uuidString.prefix(8), privacy: .public) — skipping")
            return
        }

        storedDrops[drop.id] = drop
        saveToDisk()
        logger.info("Stored relay drop \(drop.id.uuidString.prefix(8), privacy: .public) from \(drop.senderName, privacy: .public)")
    }

    private func handlePickupPacket(_ data: Data) {
        guard let pickup = DeadDropPickup.from(payload: data) else {
            logger.warning("Failed to decode DPK! packet")
            return
        }

        if storedDrops.removeValue(forKey: pickup.dropID) != nil {
            saveToDisk()
            logger.info("Removed picked-up drop \(pickup.dropID.uuidString.prefix(8), privacy: .public)")
        }
    }

    // MARK: - Storage routing

    /// Determine whether this node should relay-store a drop based on geohash
    /// prefix proximity to our current location.
    private func shouldStore(_ drop: DeadDropMessage) -> Bool {
        guard let location = locationService?.currentLocation else {
            // No GPS — store optimistically.
            return true
        }

        let ourHash = Geohash.encode(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            precision: 4
        )
        return ourHash == drop.geohashPrefix
    }

    // MARK: - Plaintext parsing

    /// Extract the human-readable text from decrypted plaintext.
    ///
    /// If a chain hint is appended (separated by 0x00), only the text portion
    /// before the separator is returned.
    private func parsePlaintext(_ data: Data) -> String {
        if let separatorIndex = data.firstIndex(of: 0x00) {
            let textData = data[data.startIndex..<separatorIndex]
            return String(data: Data(textData), encoding: .utf8) ?? "<unreadable>"
        }
        return String(data: data, encoding: .utf8) ?? "<unreadable>"
    }

    // MARK: - Persistence

    private struct PersistedState: Codable {
        let storedDrops: [DeadDropMessage]
        let myDrops: [DeadDropMessage]
        let pickedUpMessages: [String: String]  // UUID string -> decrypted text
    }

    private func saveToDisk() {
        do {
            // Convert UUID keys to strings for Codable compliance.
            let pickupStrings = Dictionary(
                uniqueKeysWithValues: pickedUpMessages.map { ($0.key.uuidString, $0.value) }
            )
            let state = PersistedState(
                storedDrops: Array(storedDrops.values),
                myDrops: myDrops,
                pickedUpMessages: pickupStrings
            )
            let data = try MeshCodable.encoder.encode(state)
            try data.write(to: storageURL, options: .atomic)
            logger.debug("Saved dead drop state to disk")
        } catch {
            logger.error("Failed to save dead drop state: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let state = try MeshCodable.decoder.decode(PersistedState.self, from: data)

            let now = Date()

            // Rebuild storedDrops dictionary, filtering expired.
            storedDrops = [:]
            for drop in state.storedDrops where drop.expiresAt > now {
                storedDrops[drop.id] = drop
            }

            myDrops = state.myDrops.filter { $0.expiresAt > now }

            // Restore picked-up messages (UUID keys).
            pickedUpMessages = [:]
            for (idString, text) in state.pickedUpMessages {
                if let uuid = UUID(uuidString: idString) {
                    pickedUpMessages[uuid] = text
                }
            }

            let totalLoaded = storedDrops.count + myDrops.count
            if totalLoaded > 0 {
                logger.info("Loaded \(totalLoaded) dead drop(s) from disk")
            }
        } catch {
            logger.error("Failed to load dead drop state: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var storageURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dead_drops.json")
    }

    // MARK: - Helpers

    private static func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }
}
