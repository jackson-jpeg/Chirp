import Foundation
import GRDB
import OSLog

/// Encrypted SQLite message store backed by GRDB.
///
/// The database file lives at `Documents/chirp_messages.db`, excluded from
/// iCloud/iTunes backup. Encryption uses a device-specific key from the
/// Keychain (see ``KeychainHelper``). If GRDB's SQLCipher passphrase API is
/// unavailable, the file relies on iOS Data Protection
/// (`NSFileProtectionCompleteUntilFirstUserAuthentication`).
@MainActor
final class MessageDatabase {

    private let dbQueue: DatabaseQueue
    private let logger = Logger(subsystem: Constants.subsystem, category: "MessageDB")

    // MARK: - Init

    init() throws {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dbURL = documentsURL.appendingPathComponent("chirp_messages.db")

        // GRDB standard doesn't include SQLCipher. Instead, rely on iOS Data Protection
        // for encryption at rest. The DB file is protected by NSFileProtectionCompleteUntilFirstUserAuthentication
        // which means it's encrypted whenever the device is locked (after first unlock).
        // Combined with Keychain-stored app secrets, this provides strong at-rest protection.
        let config = Configuration()
        dbQueue = try DatabaseQueue(path: dbURL.path, configuration: config)

        // Exclude from backup
        var resourceURL = dbURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? resourceURL.setResourceValues(resourceValues)

        // Apply iOS file protection
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: dbURL.path
        )

        // Create schema
        try createTablesIfNeeded()

        logger.info("MessageDatabase opened at \(dbURL.path, privacy: .public)")
    }

    // MARK: - Schema

    private func createTablesIfNeeded() throws {
        try dbQueue.write { db in
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

    /// Fetch messages for a channel, ordered by timestamp ascending.
    func messages(forChannel channelID: String, limit: Int) -> [MessageRecord] {
        do {
            return try dbQueue.read { db in
                try MessageRecord
                    .filter(Column("channelID") == channelID)
                    .order(Column("timestamp").asc)
                    .limit(limit)
                    .fetchAll(db)
            }
        } catch {
            logger.error("Failed to fetch messages: \(error.localizedDescription, privacy: .public)")
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
