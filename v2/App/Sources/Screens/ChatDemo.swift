import SwiftUI
import ChirpCore

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

    /// A text's own ID when it came from the air, so rows keep their identity
    /// as ticks arrive.
    var id = UUID()
    var sender: ChatSender
    var kind: Kind
    var status: Status?
}

/// A row of the chat: a message, or a quiet line about the birdhouse.
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
                sender: .person(Birdhouse.maya),
                kind: .voice(seconds: 6,
                             caption: "We got a table by the fire. Lodge, second floor, come up when you're done.",
                             bars: mayaBars, played: 6))),
            .message(ChatMessage(sender: .person(Birdhouse.jon), kind: .text("Lift 4 in 10?"))),
            .message(ChatMessage(sender: .you, kind: .text("On my way, save me a seat"),
                                 status: .heardBy([Birdhouse.maya, Birdhouse.jon, Birdhouse.priya]))),
            .message(ChatMessage(sender: .person(Birdhouse.priya), kind: .text("Grabbing the boards first, 15 min"))),
        ]
    }

    /// The texts dispatch stored for one channel, oldest first, as rows.
    /// The sender is the person on the line with that key, else a bird made
    /// from the name the text carried (they may have gone out of range).
    /// Your texts say "Sent" until someone acks, then who heard them.
    static func from(_ texts: [StoredText], channel: ChannelID, birdhouse: Birdhouse) -> [ChatItem] {
        func person(_ hex: String, name: String) -> Person {
            birdhouse.others.first { $0.peer?.hex == hex }
                ?? Person(id: hex, name: name.isEmpty ? "Someone" : name, palette: .yellow, peer: PeerID(hex: hex))
        }
        return texts
            .filter { $0.channel == channel.uuid }
            .sorted { $0.sentAt < $1.sentAt }
            .map { t in
                if t.outgoing {
                    let heard = t.deliveredTo.sorted().map { hex in person(hex, name: "") }
                    return .message(ChatMessage(id: t.id, sender: .you, kind: .text(t.text),
                                                status: heard.isEmpty ? .sent : .heardBy(heard)))
                }
                return .message(ChatMessage(id: t.id, sender: .person(person(t.sender, name: t.senderName)),
                                            kind: .text(t.text)))
            }
    }

    /// A waveform for a new voice message of yours.
    static func bars(forSeconds s: Int) -> [CGFloat] {
        let pattern: [CGFloat] = [6, 12, 18, 10, 16, 8, 14, 20, 10, 6]
        let count = min(15, max(5, s * 3))
        return (0..<count).map { pattern[$0 % pattern.count] }
    }
}
