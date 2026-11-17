import SwiftUI

/// Who wrote a message.
enum ChatSender: Equatable {
    case you
    case person(Person)
}

/// One message on the chat line.
struct ChatMessage: Identifiable {
    enum Kind {
        case text(String)
        /// A voice message, its length, the words it said, and its waveform.
        case voice(seconds: Int, caption: String?, bars: [CGFloat], played: Int)
    }

    /// Only for your own messages: who has heard it.
    enum Status {
        case sent
        case heardBy([Person])
    }

    let id = UUID()
    var sender: ChatSender
    var kind: Kind
    var status: Status?
}

/// A row of the chat: a message, or a quiet line about the flock.
enum ChatItem: Identifiable {
    case event(id: UUID, text: String)
    case message(ChatMessage)

    var id: UUID {
        switch self {
        case .event(let id, _): id
        case .message(let m): m.id
        }
    }
}

extension ChatItem {
    /// Maya's waveform in `Chat.dc.html`: 15 bars, the first 6 played.
    static let mayaBars: [CGFloat] = [6, 14, 20, 12, 18, 8, 16, 10, 20, 12, 6, 14, 18, 10, 6]

    /// The conversation exactly as `Chat.dc.html` shows it.
    static func demo() -> [ChatItem] {
        [
            .event(id: UUID(), text: "Priya joined the line · 9:41"),
            .message(ChatMessage(
                sender: .person(Flock.maya),
                kind: .voice(seconds: 6,
                             caption: "We got a table by the fire. Lodge, second floor, come up when you're done.",
                             bars: mayaBars, played: 6))),
            .message(ChatMessage(sender: .person(Flock.jon), kind: .text("Lift 4 in 10?"))),
            .message(ChatMessage(sender: .you, kind: .text("On my way, save me a seat"),
                                 status: .heardBy([Flock.maya, Flock.jon, Flock.priya]))),
            .message(ChatMessage(sender: .person(Flock.priya), kind: .text("Grabbing the boards first, 15 min"))),
        ]
    }

    /// A waveform for a new voice message of yours.
    static func bars(forSeconds s: Int) -> [CGFloat] {
        let pattern: [CGFloat] = [6, 12, 18, 10, 16, 8, 14, 20, 10, 6]
        let count = min(15, max(5, s * 3))
        return (0..<count).map { pattern[$0 % pattern.count] }
    }
}
