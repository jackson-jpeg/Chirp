import Foundation
import GRDB
import OSLog

// MARK: - GRDB Record Types

/// GRDB record mapping for the `breadcrumbs` table.
struct BreadcrumbRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "breadcrumbs"

    let id: String
    let trailID: String
    let peerID: String
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let source: Int
    let timestamp: String
    let floorLevel: Int?

    // MARK: - Converters

    init(from crumb: Breadcrumb, trailID: String) {
        self.id = crumb.id.uuidString
        self.trailID = trailID
        self.peerID = crumb.peerID
        self.latitude = crumb.latitude
        self.longitude = crumb.longitude
        self.accuracy = crumb.accuracyMeters
        self.source = Int(crumb.source.rawValue)
        self.timestamp = ISO8601DateFormatter().string(from: crumb.timestamp)
        self.floorLevel = crumb.floorLevel
    }

    func toBreadcrumb() -> Breadcrumb? {
        guard let uuid = UUID(uuidString: id),
              let sourceValue = PositionEstimate.PositionSource(rawValue: UInt8(source)),
              let date = ISO8601DateFormatter().date(from: timestamp) else {
            return nil
        }
        // Reconstruct using memberwise init — Breadcrumb generates its own UUID,
        // but we need the stored one. Use a helper approach:
        return Breadcrumb(
            storedID: uuid,
            peerID: peerID,
            latitude: latitude,
            longitude: longitude,
            accuracyMeters: accuracy,
            source: sourceValue,
            timestamp: date,
            floorLevel: floorLevel
        )
    }
}

/// GRDB record mapping for the `fingerprints` table.
struct FingerprintRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "fingerprints"

    let id: String
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let floorLevel: Int?
    let observations: String   // JSON-encoded [RadioObservation]
    let timestamp: String
    let contributorPeerID: String

    // MARK: - Converters

    init(from fp: WiFiFingerprint) {
        self.id = fp.id.uuidString
        self.latitude = fp.latitude
        self.longitude = fp.longitude
        self.accuracy = fp.accuracyMeters
        self.floorLevel = fp.floorLevel
        self.observations = (try? String(
            data: MeshCodable.encoder.encode(fp.observations),
            encoding: .utf8
        )) ?? "[]"
        self.timestamp = ISO8601DateFormatter().string(from: fp.timestamp)
        self.contributorPeerID = fp.contributorPeerID
    }

    func toWiFiFingerprint() -> WiFiFingerprint? {
        guard let uuid = UUID(uuidString: id),
              let date = ISO8601DateFormatter().date(from: timestamp),
              let jsonData = observations.data(using: .utf8),
              let obs = try? MeshCodable.decoder.decode([RadioObservation].self, from: jsonData) else {
            return nil
        }
        return WiFiFingerprint(
            storedID: uuid,
            latitude: latitude,
            longitude: longitude,
            accuracyMeters: accuracy,
            floorLevel: floorLevel,
            observations: obs,
            contributorPeerID: contributorPeerID,
            timestamp: date
        )
    }
}

// MARK: - LighthouseDatabase

/// GRDB-backed database for LIGHTHOUSE indoor positioning data.
///
/// Stores breadcrumb trails and WiFi/BLE fingerprints collected by
/// the mesh network. Data is used for crowd-sourced indoor positioning
/// when GPS is unavailable.
@MainActor
final class LighthouseDatabase {

    private let dbQueue: DatabaseQueue
    private let logger = Logger(subsystem: Constants.subsystem, category: "LighthouseDB")

    // MARK: - Init

    init() throws {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw DatabaseError.documentsDirectoryUnavailable
        }
        let dbURL = documentsURL.appendingPathComponent("lighthouse.db")

        var config = Configuration()
        #if DEBUG
        config.prepareDatabase { db in
            db.trace { Logger.database.debug("SQL: \($0)") }
        }
        #endif

        dbQueue = try DatabaseQueue(path: dbURL.path, configuration: config)

        // Exclude from iCloud/iTunes backup
        var resourceURL = dbURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? resourceURL.setResourceValues(resourceValues)

        // iOS file protection
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: dbURL.path
        )

        try createTablesIfNeeded()

        logger.info("LighthouseDatabase opened at \(dbURL.path, privacy: .public)")
    }

    // MARK: - Schema

    private func createTablesIfNeeded() throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS breadcrumbs (
                    id TEXT PRIMARY KEY,
                    trailID TEXT NOT NULL,
                    peerID TEXT NOT NULL,
                    latitude REAL NOT NULL,
                    longitude REAL NOT NULL,
                    accuracy REAL NOT NULL,
                    source INTEGER NOT NULL,
                    timestamp TEXT NOT NULL,
                    floorLevel INTEGER
                )
                """)

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_breadcrumbs_location
                ON breadcrumbs(latitude, longitude)
                """)

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_breadcrumbs_trail
                ON breadcrumbs(trailID)
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS fingerprints (
                    id TEXT PRIMARY KEY,
                    latitude REAL NOT NULL,
                    longitude REAL NOT NULL,
                    accuracy REAL NOT NULL,
                    floorLevel INTEGER,
                    observations TEXT NOT NULL,
                    timestamp TEXT NOT NULL,
                    contributorPeerID TEXT NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_fingerprints_location
                ON fingerprints(latitude, longitude)
                """)
        }
    }

    // MARK: - Insert

    /// Persist a breadcrumb to the database. The trail ID associates it with
    /// a recording session.
    func saveBreadcrumb(_ crumb: Breadcrumb, trailID: String) {
        let record = BreadcrumbRecord(from: crumb, trailID: trailID)
        do {
            try dbQueue.write { db in
                try record.insert(db, onConflict: .replace)
            }
        } catch {
            logger.error("Failed to save breadcrumb: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Persist a WiFi/BLE fingerprint to the database.
    func saveFingerprint(_ fp: WiFiFingerprint) {
        let record = FingerprintRecord(from: fp)
        do {
            try dbQueue.write { db in
                try record.insert(db, onConflict: .replace)
            }
        } catch {
            logger.error("Failed to save fingerprint: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Spatial Queries

    /// Find fingerprints within a radius of a coordinate.
    ///
    /// Uses a bounding-box pre-filter on the indexed lat/lon columns,
    /// then refines with Haversine distance in Swift.
    func findFingerprints(
        near latitude: Double,
        longitude: Double,
        radiusMeters: Double
    ) -> [WiFiFingerprint] {
        let (minLat, maxLat, minLon, maxLon) = boundingBox(
            latitude: latitude, longitude: longitude, radiusMeters: radiusMeters
        )

        do {
            let records = try dbQueue.read { db in
                try FingerprintRecord
                    .filter(
                        Column("latitude") >= minLat
                        && Column("latitude") <= maxLat
                        && Column("longitude") >= minLon
                        && Column("longitude") <= maxLon
                    )
                    .fetchAll(db)
            }

            return records.compactMap { record in
                guard let fp = record.toWiFiFingerprint() else { return nil }
                let dist = haversineDistance(
                    lat1: latitude, lon1: longitude,
                    lat2: fp.latitude, lon2: fp.longitude
                )
                return dist <= radiusMeters ? fp : nil
            }
        } catch {
            logger.error("Failed to find fingerprints: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Find breadcrumbs within a radius of a coordinate.
    func findBreadcrumbs(
        near latitude: Double,
        longitude: Double,
        radiusMeters: Double
    ) -> [Breadcrumb] {
        let (minLat, maxLat, minLon, maxLon) = boundingBox(
            latitude: latitude, longitude: longitude, radiusMeters: radiusMeters
        )

        do {
            let records = try dbQueue.read { db in
                try BreadcrumbRecord
                    .filter(
                        Column("latitude") >= minLat
                        && Column("latitude") <= maxLat
                        && Column("longitude") >= minLon
                        && Column("longitude") <= maxLon
                    )
                    .fetchAll(db)
            }

            return records.compactMap { record in
                guard let crumb = record.toBreadcrumb() else { return nil }
                let dist = haversineDistance(
                    lat1: latitude, lon1: longitude,
                    lat2: crumb.latitude, lon2: crumb.longitude
                )
                return dist <= radiusMeters ? crumb : nil
            }
        } catch {
            logger.error("Failed to find breadcrumbs: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Trail Queries

    /// Fetch the most recent breadcrumbs for a specific peer, ordered newest-first.
    func recentBreadcrumbs(forPeer peerID: String, limit: Int = 50) -> [Breadcrumb] {
        do {
            let records = try dbQueue.read { db in
                try BreadcrumbRecord
                    .filter(Column("peerID") == peerID)
                    .order(Column("timestamp").desc)
                    .limit(limit)
                    .fetchAll(db)
            }
            // Reverse so oldest is first (for polyline drawing order).
            return records.compactMap { $0.toBreadcrumb() }.reversed()
        } catch {
            logger.error("Failed to fetch breadcrumbs for peer \(peerID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Return all distinct peer IDs that have breadcrumb data.
    func allBreadcrumbPeerIDs() -> [String] {
        do {
            return try dbQueue.read { db in
                try String.fetchAll(db, sql: "SELECT DISTINCT peerID FROM breadcrumbs")
            }
        } catch {
            logger.error("Failed to fetch peer IDs: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Maintenance

    /// Delete breadcrumbs and fingerprints older than the specified number of days.
    func pruneOlderThan(days: Int) {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let cutoffString = ISO8601DateFormatter().string(from: cutoffDate)

        do {
            try dbQueue.write { db in
                try db.execute(
                    sql: "DELETE FROM breadcrumbs WHERE timestamp < ?",
                    arguments: [cutoffString]
                )
                try db.execute(
                    sql: "DELETE FROM fingerprints WHERE timestamp < ?",
                    arguments: [cutoffString]
                )
            }
            logger.info("Pruned LIGHTHOUSE data older than \(days, privacy: .public) days")
        } catch {
            logger.error("Failed to prune: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Counts

    /// Total number of breadcrumbs stored.
    var totalBreadcrumbs: Int {
        do {
            return try dbQueue.read { db in
                try BreadcrumbRecord.fetchCount(db)
            }
        } catch {
            logger.error("Failed to count breadcrumbs: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    /// Total number of fingerprints stored.
    var totalFingerprints: Int {
        do {
            return try dbQueue.read { db in
                try FingerprintRecord.fetchCount(db)
            }
        } catch {
            logger.error("Failed to count fingerprints: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    // MARK: - Private Helpers

    /// Compute a lat/lon bounding box for a given radius in meters.
    /// Approximation suitable for spatial pre-filtering.
    private func boundingBox(
        latitude: Double,
        longitude: Double,
        radiusMeters: Double
    ) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        // 1 degree latitude ~ 111,320 meters
        let latDelta = radiusMeters / 111_320.0
        // 1 degree longitude varies by latitude
        let lonDelta = radiusMeters / (111_320.0 * cos(latitude * .pi / 180))

        return (
            minLat: latitude - latDelta,
            maxLat: latitude + latDelta,
            minLon: longitude - lonDelta,
            maxLon: longitude + lonDelta
        )
    }

    /// Haversine distance between two coordinates in meters.
    private func haversineDistance(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        let earthRadius = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
                sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadius * c
    }
}
