import Foundation

// When the audio session is open, as a pure function (App Review 2.5.4).
//
// 1.0 was rejected under 2.5.4: it declared the `audio` background mode and
// activated a play-and-record session with a live input node at launch, never
// releasing it (audit section 6). 2.0 declares no background mode and holds
// the session only while it is needed:
// - record (microphone live) only while this device holds the floor,
// - playback only while someone on the open channel is talking, plus a short
//   tail so the jitter buffer drains,
// - nothing in the background, nothing during an interruption,
// - nothing at launch: the first activation follows a press or a speaker.
//
// The app's audio session code becomes a thin adapter: on every change of
// these inputs it asks `need`, and moves the real AVAudioSession to match.

public enum AudioSessionNeed: Equatable, Sendable {
    case off
    /// Output only (no microphone, no indicator).
    case playback
    /// Microphone and output (the orange indicator shows).
    case record
}

public struct AudioSessionInputs: Equatable, Sendable {
    public var foreground: Bool
    /// Between an interruption's begin and end (a call, Siri).
    public var interrupted: Bool
    public var floor: FloorState
    /// When the last speaker's turn ended, if one ended recently.
    public var lastSpeechEnded: Date?

    public init(foreground: Bool, interrupted: Bool = false, floor: FloorState = .idle, lastSpeechEnded: Date? = nil) {
        self.foreground = foreground
        self.interrupted = interrupted
        self.floor = floor
        self.lastSpeechEnded = lastSpeechEnded
    }
}

public enum AudioSessionPolicy {
    /// Playback stays open this long after a speaker stops, to drain the
    /// jitter buffer and avoid re-activating between quick turns.
    public static let playbackTail: TimeInterval = 2

    public static func need(_ i: AudioSessionInputs, now: Date) -> AudioSessionNeed {
        guard i.foreground, !i.interrupted else { return .off }
        if i.floor.microphoneIsOpen { return .record }
        if i.floor.speaker != nil { return .playback }
        if let ended = i.lastSpeechEnded, now.timeIntervalSince(ended) < playbackTail { return .playback }
        return .off
    }
}
