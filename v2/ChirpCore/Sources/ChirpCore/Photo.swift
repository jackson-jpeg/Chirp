import Foundation

/// Small photos (scope item 5): the app shrinks a photo to at most
/// `maxBytes` (HEIC or JPEG, its choice) and sends it in chunks. Each chunk is
/// a `.photo` packet on the chat's channel (sealed if the channel is locked),
/// and `PhotoAssembler` puts them back together.
///
/// 1.0 had two image paths (base64 inside a 100,000-character text, and a
/// separate file transfer service, audit section 5). This is the only one.
/// Photos reach at most one relay (TTL 2) and go last in the send queue, so
/// they never hold up voice, help or texts.
public struct PhotoChunk: Equatable, Sendable {
    public static let maxBytes = 48 * 1024
    public static let chunkBytes = 8 * 1024
    public static var maxChunks: Int { (maxBytes + chunkBytes - 1) / chunkBytes }

    public let photoID: UUID
    public let index: UInt8
    public let count: UInt8
    public let bytes: Data

    /// Chunks for one photo, or nil if it is empty or over `maxBytes`.
    public static func split(_ photo: Data, id: UUID = UUID()) -> [PhotoChunk]? {
        guard !photo.isEmpty, photo.count <= maxBytes else { return nil }
        let bytes = [UInt8](photo)
        let n = (bytes.count + chunkBytes - 1) / chunkBytes
        return (0..<n).map { i in
            let range = (i * chunkBytes)..<min(bytes.count, (i + 1) * chunkBytes)
            return PhotoChunk(photoID: id, index: UInt8(i), count: UInt8(n), bytes: Data(bytes[range]))
        }
    }

    public func encode() -> Data {
        var d = withUnsafeBytes(of: photoID.uuid) { Data($0) }
        d.append(index); d.append(count)
        d.appendBigEndian(UInt16(bytes.count)); d.append(bytes)
        return d
    }

    public static func decode(_ data: Data) -> PhotoChunk? {
        var r = ByteReader(data)
        guard let idb = r.bytes(16).map([UInt8].init), let index = r.u8(), let count = r.u8(),
              count >= 1, Int(count) <= maxChunks, index < count,
              let n = r.u16(), n >= 1, Int(n) <= chunkBytes, let bytes = r.bytes(Int(n)), r.isAtEnd else { return nil }
        let id = UUID(uuid: (idb[0], idb[1], idb[2], idb[3], idb[4], idb[5], idb[6], idb[7],
                             idb[8], idb[9], idb[10], idb[11], idb[12], idb[13], idb[14], idb[15]))
        return PhotoChunk(photoID: id, index: index, count: count, bytes: bytes)
    }
}

/// Collects chunks until a photo is whole. Bounded in photos in flight and
/// in time, so a peer that sends first chunks and never the rest cannot make
/// this phone hold data forever.
public struct PhotoAssembler: Sendable {
    public static let timeout: TimeInterval = 60
    public let maxInFlight: Int

    private struct Key: Hashable { let origin: PeerID; let id: UUID }
    private struct Partial { var count: UInt8; var parts: [UInt8: Data]; let started: Date }
    private var partial: [Key: Partial] = [:]
    private var done: Set<Key> = []

    public init(maxInFlight: Int = 8) { self.maxInFlight = maxInFlight }

    public var inFlight: Int { partial.count }

    /// The whole photo when this chunk completes it, else nil.
    public mutating func add(_ chunk: PhotoChunk, from origin: PeerID, now: Date) -> Data? {
        partial = partial.filter { now.timeIntervalSince($0.value.started) < Self.timeout }
        let key = Key(origin: origin, id: chunk.photoID)
        guard !done.contains(key) else { return nil }
        var p = partial[key] ?? Partial(count: chunk.count, parts: [:], started: now)
        guard p.count == chunk.count else { return nil }         // inconsistent chunk: ignore
        if partial[key] == nil, partial.count >= maxInFlight,
           let oldest = partial.min(by: { $0.value.started < $1.value.started })?.key {
            partial.removeValue(forKey: oldest)
        }
        p.parts[chunk.index] = chunk.bytes
        guard p.parts.count == Int(p.count) else { partial[key] = p; return nil }
        partial.removeValue(forKey: key)
        done.insert(key)
        if done.count > 1024 { done.removeAll() }
        return (0..<p.count).reduce(into: Data()) { $0.append(p.parts[$1]!) }
    }
}
