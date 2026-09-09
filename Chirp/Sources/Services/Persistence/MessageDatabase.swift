import Foundation
import GRDB
import OSLog

/// Errors that can occur during database initialization.
enum DatabaseError: Error, LocalizedError {
    case documentsDirectoryUnavailable

    var errorDescription: String? {
        switch self {
        case .documentsDirectoryUnavailable:
            return "Documents directory is unavailable."
        }
    }
}

/// SQLite message store backed by GRDB.
///
/// The database file lives at `Documents/chirp_messages.db`, excluded from
/// iCloud/iTunes backup. At-rest protection is iOS Data Protection
/// (`NSFileProtectionCompleteUntilFirstUserAuthentication`) — the file is
/// encrypted whenever the device is locked, after first unlock.
///
/// Schema changes go through ``migrator``: append a new
/// `registerMigration` block, never edit an existing one. GRDB records which
/// migrations have run, so existing installs pick up only what's new.
@MainActor
final class MessageDatabase {

    private let dbQueue: DatabaseQueue
    private let logger = Logger(subsystem: Constants.subsystem, category: "MessageDB")

    // MARK: - Init

    init() throws {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw DatabaseError.documentsDirectoryUnavailable
        }
        let dbURL = documentsURL.appendingPathComponent("chirp_messages.db")

        let config = Configuration()
        dbQueue = try DatabaseQueue(path: dbURL.path, configuration: config)

        // Exclude from backup. Failing is survivable (the store still works),
        // but it means message history would land in device backups.
        do {
            var resourceURL = dbURL
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try resourceURL.setResourceValues(resourceValues)
        } catch {
            logger.error("Could not exclude database from backup: \(error.localizedDescription, privacy: .public)")
        }

        // Apply iOS file protection — this is the at-rest encryption story,
        // so a failure is worth more than silence.
        do {
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: dbURL.path
            )
        } catch {
            logger.error("Could not apply file protection to database: \(error.localizedDescription, privacy: .public)")
        }

        try Self.migrator.migrate(dbQueue)

        logger.info("MessageDatabase opened at \(dbURL.path, privacy: .public)")
    }

    // MARK: - Schema

    /// All schema history, in order. v1 is the schema as shipped in 1.0.0.
    ///
    /// The v1 statements keep `IF NOT EXISTS` because installs from before the
    /// migrator existed already have the table but no migration record; v1 must
    /// re-run cleanly on them. Later migrations start from a recorded state and
    /// should not need that guard.
    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS messages (
                    id TEXT PRIMARY KEY,
                    senderID TEXT NOT NULL,
                    senderName TEXT NOT NULL,
                    channelID TEXT NOT NULL,
                    text TEXT NOT NULL,
                    timestamp TEXT NOT NULL,
                    replyToID TEXT,
                    attachmentType TEXT
                )
                """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_messages_channel
                ON messages(channelID, timestamp)
                """)
        }

        return migrator
    }

    // MARK: - Insert

    /// Insert a message record, ignoring duplicates (dedup by primary key).
    func insert(_ record: MessageRecord) {
        do {
            try dbQueue.write { db in
                try record.insert(db, onConflict: .ignore)
            }
        } catch {
            logger.error("Failed to insert message: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Queries

    /// Fetch the most recent messages for a channel, ordered by timestamp ascending.
    func messages(forChannel channelID: String, limit: Int) -> [MessageRecord] {
        do {
            // Subquery: grab the N newest rows, then re-sort ascending.
            return try dbQueue.read { db in
                let rows = try MessageRecord
                    .filter(Column("channelID") == channelID)
                    .order(Column("timestamp").desc)
                    .limit(limit)
                    .fetchAll(db)
                return rows.reversed()
            }
        } catch {
            logger.error("Failed to fetch messages: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Fetch messages older than the given ISO 8601 timestamp, ordered ascending.
    /// Used for paginating backwards through history.
    func messagesBefore(
        timestamp: String,
        forChannel channelID: String,
        limit: Int
    ) -> [MessageRecord] {
        do {
            return try dbQueue.read { db in
                let rows = try MessageRecord
                    .filter(Column("channelID") == channelID && Column("timestamp") < timestamp)
                    .order(Column("timestamp").desc)
                    .limit(limit)
                    .fetchAll(db)
                return rows.reversed()
            }
        } catch {
            logger.error("Failed to fetch older messages: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Count messages in a channel.
    func messageCount(forChannel channelID: String) -> Int {
        do {
            return try dbQueue.read { db in
                try MessageRecord
                    .filter(Column("channelID") == channelID)
                    .fetchCount(db)
            }
        } catch {
            logger.error("Failed to count messages: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    /// Delete the oldest messages in a channel, keeping only `keepCount`.
    func deleteOldest(forChannel channelID: String, keepCount: Int) {
        do {
            try dbQueue.write { db in
                // Find the timestamp of the Nth newest message.
                let cutoffRows = try MessageRecord
                    .filter(Column("channelID") == channelID)
                    .order(Column("timestamp").desc)
                    .limit(1, offset: keepCount - 1)
                    .fetchAll(db)

                guard let cutoff = cutoffRows.first else { return }

                // Delete everything older than that timestamp.
                try db.execute(
                    sql: """
                        DELETE FROM messages
                        WHERE channelID = ? AND timestamp < ?
                        """,
                    arguments: [channelID, cutoff.timestamp]
                )
            }
        } catch {
            logger.error("Failed to trim messages: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Fetch a single message by ID.
    func message(byID id: String) -> MessageRecord? {
        do {
            return try dbQueue.read { db in
                try MessageRecord.fetchOne(db, key: id)
            }
        } catch {
            logger.error("Failed to fetch message by ID: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Fetch all messages in a thread (the parent + all replies to it).
    func messagesInThread(parentID: String, channelID: String) -> [MessageRecord] {
        do {
            return try dbQueue.read { db in
                try MessageRecord
                    .filter(
                        Column("channelID") == channelID
                        && (Column("id") == parentID || Column("replyToID") == parentID)
                    )
                    .order(Column("timestamp").asc)
                    .fetchAll(db)
            }
        } catch {
            logger.error("Failed to fetch thread: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
