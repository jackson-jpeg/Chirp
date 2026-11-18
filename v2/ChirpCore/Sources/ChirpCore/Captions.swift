import Foundation

// Live captions (scope 2): on-device speech to text of every voice message, and
// a captions-only mode for loud concerts or a sleeping tent.
//
// Three rules live here so each has a test:
// - The speech permission is asked on the first tap of captions, never at
//   launch (App Review 5.1.1(iv)). Reading the current status is an input;
//   only a tap produces `.requestPermission`.
// - Captions are made on the phone or not at all: with no on-device recognizer
//   for the language, captions are unavailable (nothing is sent to a server).
// - Captions-only never silences a message it cannot caption: audio plays
//   unless captions are really being made.

public enum CaptionMode: String, Sendable, CaseIterable {
    /// No captions; voice plays.
    case off
    /// Captions under every voice message; voice plays. The default.
    case on
    /// Captions only; voice does not play (when captions are being made).
    case only
}

public enum SpeechPermission: Sendable, Equatable {
    case notAsked
    case granted
    /// Denied or restricted in Settings.
    case denied
    /// No on-device recognizer for this language on this phone.
    case unavailable
}

public struct CaptionSettings: Equatable, Sendable {
    public var mode: CaptionMode
    public var permission: SpeechPermission
    public init(mode: CaptionMode = .on, permission: SpeechPermission = .notAsked) {
        self.mode = mode
        self.permission = permission
    }
}

public enum CaptionEvent: Equatable, Sendable {
    /// The user tapped the "Turn on captions" offer on a caption card.
    case tappedCaptions
    /// The user picked a mode.
    case chose(CaptionMode)
    /// The iOS prompt was answered.
    case permissionAnswered(granted: Bool)
    /// The status read from iOS (at launch, on returning to the app). Never asks.
    case permissionChecked(SpeechPermission)
}

public enum CaptionEffect: Equatable, Sendable {
    case requestPermission
    /// Denied in Settings; tell the user where to change it.
    case explainDenied
    /// No on-device captions for this language.
    case explainUnavailable
}

/// What a caption card shows under a voice message.
public enum CaptionCard: Equatable, Sendable {
    /// Captions are off: no caption line.
    case hidden
    /// Captions are wanted but never asked for: a "Turn on captions" button.
    case offer
    /// Captions are being made.
    case captioning
    /// Denied in Settings.
    case denied
    /// No on-device recognizer.
    case unavailable
}

public enum Captions {
    public static func reduce(_ s: CaptionSettings, _ e: CaptionEvent) -> (CaptionSettings, [CaptionEffect]) {
        var s = s
        switch e {
        case .tappedCaptions:
            if s.mode == .off { s.mode = .on }
            return (s, effectsForWanting(s.permission))
        case .chose(let mode):
            s.mode = mode
            return (s, mode == .off ? [] : effectsForWanting(s.permission))
        case .permissionAnswered(let granted):
            // An answer cannot make captions available where there is no
            // on-device recognizer.
            if s.permission != .unavailable { s.permission = granted ? .granted : .denied }
            return (s, [])
        case .permissionChecked(let p):
            s.permission = p
            return (s, [])
        }
    }

    private static func effectsForWanting(_ p: SpeechPermission) -> [CaptionEffect] {
        switch p {
        case .notAsked: [.requestPermission]
        case .granted: []
        case .denied: [.explainDenied]
        case .unavailable: [.explainUnavailable]
        }
    }

    /// Whether received and sent voice is being turned into text.
    public static func captioning(_ s: CaptionSettings) -> Bool {
        s.mode != .off && s.permission == .granted
    }

    /// Whether voice plays out loud. Captions-only silences only what is captioned.
    public static func playsAudio(_ s: CaptionSettings) -> Bool {
        !(s.mode == .only && captioning(s))
    }

    public static func card(_ s: CaptionSettings) -> CaptionCard {
        guard s.mode != .off else { return .hidden }
        switch s.permission {
        case .notAsked: return .offer
        case .granted: return .captioning
        case .denied: return .denied
        case .unavailable: return .unavailable
        }
    }
}

/// The captions of the most recent voice streams, one per speaker stream
/// (peer and epoch, as in `JitterBuffer`). A recognizer reports the whole text
/// so far each time, so an update replaces; a final result closes the stream,
/// and anything the recognizer sends after it is ignored. Holds at most `cap`
/// streams, dropping the oldest.
///
/// A phone keeps one epoch for as long as the app runs, so the same speaker
/// key comes back for every turn a person takes. `begin` opens a fresh
/// caption for the new turn; updates go to the newest caption of a key.
public struct CaptionTrack: Sendable, Equatable {
    public typealias Speaker = JitterBuffer.Speaker

    public struct Caption: Equatable, Sendable {
        public let speaker: Speaker
        public var text: String
        public var final: Bool
        public var updated: Date
    }

    public let cap: Int
    public private(set) var captions: [Caption] = []

    public init(cap: Int = 32) { self.cap = max(1, cap) }

    /// A new turn from `speaker`: an empty, open caption, so the last turn's
    /// words are not shown as this one's and its updates are not refused.
    public mutating func begin(_ speaker: Speaker, at now: Date) {
        if let i = captions.lastIndex(where: { $0.speaker == speaker }), !captions[i].final,
           captions[i].text.isEmpty { return }   // already open and empty
        append(Caption(speaker: speaker, text: "", final: false, updated: now))
    }

    public mutating func update(_ speaker: Speaker, text: String, final: Bool, at now: Date) {
        if let i = captions.lastIndex(where: { $0.speaker == speaker }) {
            guard !captions[i].final else { return }
            // A final with no words keeps the last partial text.
            if !(final && text.isEmpty) { captions[i].text = text }
            captions[i].final = final
            captions[i].updated = now
            return
        }
        append(Caption(speaker: speaker, text: text, final: final, updated: now))
    }

    private mutating func append(_ c: Caption) {
        captions.append(c)
        if captions.count > cap { captions.removeFirst(captions.count - cap) }
    }

    public func caption(for speaker: Speaker) -> Caption? {
        captions.last { $0.speaker == speaker }
    }

    /// The newest caption from `peer`, whatever the epoch.
    public func latest(from peer: PeerID) -> Caption? {
        captions.last { $0.speaker.peer == peer }
    }
}
