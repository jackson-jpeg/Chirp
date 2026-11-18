import Foundation

/// The birdhouses this phone keeps: the one Talk is on (`current`) and, with
/// Big Birdhouse, others to switch back to from Talk's birdhouse menu
/// (Jackson approved "the same extras", Inbox chirp-2-0-revenue-shape; the
/// third extra in docs/proposals/revenue-2.0.md).
///
/// Free keeps one: joining another asks "Leave X and join Y?" first, and the
/// old one is gone. With Big Birdhouse the old one is kept, most recently used
/// first, up to `cap` in all. Only the current one is joined on the radio, so
/// switching leaves the old channel and joins the new one.
///
/// After a refund the kept list stays on the phone (a restore brings it back)
/// but `switchable` shows none of it, so nothing is used that is not owned.
public struct SavedBirdhouses: Equatable, Sendable {
    /// Birdhouses kept in all, the current one included.
    public static let cap = 8

    public private(set) var current: Channel?
    /// Kept birdhouses other than `current`, most recently used first.
    public private(set) var others: [Channel]
    /// Birdhouses you started (only the starter is ever asked about Big Birdhouse).
    public private(set) var started: Set<ChannelID>

    public init(current: Channel? = nil, others: [Channel] = [], started: Set<ChannelID> = []) {
        self.current = current
        var seen: Set<ChannelID> = current.map { [$0.id] } ?? []
        self.others = Array(others.filter { $0.isLocked && seen.insert($0.id).inserted }.prefix(Self.cap - 1))
        let kept = Set(([current].compactMap { $0 } + self.others).map(\.id))
        self.started = started.intersection(kept)
    }

    public var startedCurrent: Bool { current.map { started.contains($0.id) } ?? false }

    /// What starting or joining `channel` does from here.
    public enum Join: Equatable, Sendable {
        /// It is already the current birdhouse: just go to Talk.
        case alreadyIn
        /// Switch straight to it (no birdhouse yet, or Big Birdhouse keeps the old one).
        case use
        /// Free, and in another birdhouse: ask "Leave X and join Y?" first.
        case askToLeave
    }

    public func join(_ channel: Channel, unlocked: Bool) -> Join {
        guard let current else { return .use }
        if current.id == channel.id { return .alreadyIn }
        return unlocked ? .use : .askToLeave
    }

    /// Makes `channel` current. The old current is kept with Big Birdhouse and
    /// dropped without it. A kept birdhouse used again moves out of `others`.
    public mutating func use(_ channel: Channel, started startedIt: Bool, unlocked: Bool) {
        guard channel.isLocked else { return }
        let old = current
        current = channel
        others.removeAll { $0.id == channel.id }
        if let old, old.id != channel.id {
            if unlocked {
                others.insert(old, at: 0)
            } else {
                started.remove(old.id)
            }
        }
        if startedIt { started.insert(channel.id) }
        trim()
    }

    /// Talk's "Leave": the current birdhouse is gone (an invite is needed to
    /// come back). Kept ones stay.
    public mutating func leaveCurrent() {
        if let id = current?.id { started.remove(id) }
        current = nil
    }

    /// The kept birdhouses Talk's menu offers to switch to.
    public func switchable(unlocked: Bool) -> [Channel] { unlocked ? others : [] }

    /// Switches to a kept birdhouse. Nil (and no change) without Big Birdhouse
    /// or for one that is not kept.
    @discardableResult
    public mutating func switchTo(_ id: ChannelID, unlocked: Bool) -> Channel? {
        guard unlocked, let channel = others.first(where: { $0.id == id }) else { return nil }
        use(channel, started: started.contains(id), unlocked: true)
        return channel
    }

    private mutating func trim() {
        let room = current == nil ? Self.cap : Self.cap - 1
        if others.count > room {
            for dropped in others[room...] { started.remove(dropped.id) }
            others.removeLast(others.count - room)
        }
    }
}
