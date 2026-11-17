import Foundation

/// What the Lock Screen card and the Dynamic Island show (item 7, Jackson's
/// option 1): the flock, how many are on the line, who spoke last and what
/// they said. The card's button opens the app to reply; nothing on it works
/// while the phone is locked, because voice never runs in the background
/// (2.5.4).
///
/// Codable and Hashable so it can be ActivityKit's content state as is.
public struct LiveCard: Codable, Hashable, Sendable {
    public var flock: String
    /// People on the line, you not counted.
    public var onLine: Int
    /// Who talked or texted last; nil until someone has.
    public var speaker: String?
    /// Their bird's palette (`Bird.palette`), so the card draws their bird.
    public var palette: UInt8
    /// Their words: a text, or a caption of what they said. Short.
    public var line: String?
    /// True from their floor request until their release.
    public var talking: Bool

    public static let maxLine = 80

    public init(flock: String, onLine: Int, speaker: String? = nil, palette: UInt8 = 0, line: String? = nil, talking: Bool = false) {
        self.flock = flock
        self.onLine = onLine
        self.speaker = speaker
        self.palette = palette
        self.line = line.map(Self.clip)
        self.talking = talking
    }

    /// "Maya is talking", "Maya", or the flock's name before anyone spoke.
    public var headline: String {
        guard let speaker else { return flock }
        return talking ? "\(speaker) is talking" : speaker
    }

    /// "3 on the line", "Just you".
    public var count: String {
        onLine == 0 ? "Just you" : "\(onLine) on the line"
    }

    /// At most `maxLine` characters, cut at a word with an ellipsis.
    static func clip(_ s: String) -> String {
        let flat = s.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard flat.count > maxLine else { return flat }
        let cut = flat.prefix(maxLine - 1)
        let word = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return word.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters)) + "\u{2026}"
    }

    /// The card after `event`, or nil when the event does not change it.
    /// `person` gives a name and palette from the roster; strangers (not on
    /// it) never reach the card.
    public func applying(_ event: Dispatch.Event, person: (PeerID) -> (name: String, palette: UInt8)?) -> LiveCard? {
        var next = self
        switch event {
        case .floor(.request(let sender, _, _), _):
            guard let p = person(sender) else { return nil }
            next.speaker = p.name; next.palette = p.palette; next.talking = true; next.line = nil
        case .floor(.release(let sender), _):
            guard talking, let p = person(sender), p.name == speaker else { return nil }
            next.talking = false
        case .text(let t) where !t.outgoing:
            guard let peer = PeerID(hex: t.sender), let p = person(peer) else { return nil }
            next.speaker = p.name; next.palette = p.palette; next.talking = false; next.line = Self.clip(t.text)
        case .help(let h, let from, _):
            guard let p = person(from) else { return nil }
            next.speaker = p.name; next.palette = p.palette; next.talking = false
            next.line = Self.clip(h.note.isEmpty ? "Needs help" : "Needs help: \(h.note)")
        default:
            return nil
        }
        return next == self ? nil : next
    }
}

/// iOS rations Live Activity updates, so pushes are spaced: a change in who
/// is talking goes at once, anything else at most every `interval`.
public struct LiveCardPacer: Sendable {
    public static let interval: TimeInterval = 5
    private var lastPush: Date?
    private var lastPushed: LiveCard?

    public init() {}

    public mutating func shouldPush(_ card: LiveCard, now: Date) -> Bool {
        guard card != lastPushed else { return false }
        let urgent = card.talking != lastPushed?.talking || card.speaker != lastPushed?.speaker
        if !urgent, let last = lastPush, now.timeIntervalSince(last) < Self.interval { return false }
        lastPush = now
        lastPushed = card
        return true
    }
}
