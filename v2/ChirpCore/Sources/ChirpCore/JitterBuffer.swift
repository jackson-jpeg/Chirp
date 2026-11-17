import Foundation

/// Orders decoded audio frames by sequence and smooths arrival jitter.
///
/// Kept from 1.0: wait for an initial depth before playing, drop frames older
/// than the last one played, drop duplicates, trim to a maximum depth, count
/// losses. Changed: the buffer belongs to one speaker stream, (peer, epoch).
/// A frame from any other stream resets it first. In 1.0 the "last played"
/// sequence outlived the speaker, so a sender whose counter restarted after a
/// relaunch, or any later speaker with a lower counter, was dropped in silence
/// until the listener next talked (audit defect 2, claim H5).
///
/// Frames are opaque `Data` (16-bit PCM after decoding) so this has no
/// AVFoundation in it. Not thread-safe: the app owns one per playback queue.
public struct JitterBuffer: Sendable {
    public struct Speaker: Hashable, Sendable {
        public let peer: PeerID
        public let epoch: UInt32
        public init(peer: PeerID, epoch: UInt32) { self.peer = peer; self.epoch = epoch }
    }

    public struct Stats: Equatable, Sendable {
        public var received = 0
        public var lost = 0
        public var late = 0
        public var resets = 0
    }

    public let initialDepth: Int
    public let maxDepth: Int
    public private(set) var speaker: Speaker?
    public private(set) var stats = Stats()

    private var frames: [(sequence: UInt32, data: Data)] = []
    private var lastPlayed: UInt32?
    private var buffering = true

    /// Depths in frames (20 ms each): 3 frames is 60 ms, 10 is 200 ms.
    public init(initialDepth: Int = 3, maxDepth: Int = 10) {
        precondition(initialDepth >= 1 && maxDepth >= initialDepth)
        self.initialDepth = initialDepth
        self.maxDepth = maxDepth
    }

    public var count: Int { frames.count }

    public mutating func push(_ data: Data, sequence: UInt32, from speaker: Speaker) {
        if speaker != self.speaker {
            if self.speaker != nil { stats.resets += 1 }
            clear()
            self.speaker = speaker
        }
        stats.received += 1
        if let last = lastPlayed, Int32(bitPattern: sequence &- last) <= 0 {
            stats.late += 1
            return
        }
        if frames.contains(where: { $0.sequence == sequence }) { return }
        let index = frames.firstIndex { Int32(bitPattern: $0.sequence &- sequence) > 0 } ?? frames.endIndex
        frames.insert((sequence, data), at: index)
        if frames.count > maxDepth { frames.removeFirst(frames.count - maxDepth) }
    }

    /// The next frame to play, or nil while filling or when empty.
    public mutating func pull() -> Data? {
        if buffering {
            guard frames.count >= initialDepth else { return nil }
            buffering = false
        }
        guard !frames.isEmpty else {
            buffering = true
            return nil
        }
        let next = frames.removeFirst()
        if let last = lastPlayed {
            let gap = Int(Int32(bitPattern: next.sequence &- last)) - 1
            if gap > 0 { stats.lost += gap }
        }
        lastPlayed = next.sequence
        return next.data
    }

    /// Forget the stream (call when the floor goes idle).
    public mutating func reset() {
        clear()
        speaker = nil
    }

    private mutating func clear() {
        frames.removeAll()
        lastPlayed = nil
        buffering = true
    }
}
