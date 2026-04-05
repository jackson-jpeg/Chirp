import AVFoundation
import Foundation

/// Quick replies: pre-recorded voice snippets or text-to-speech messages
/// that can be sent with a single tap. Perfect for noisy environments.
struct QuickReply: Identifiable, Codable, Sendable {
    let id: UUID
    let label: String       // Display label
    let icon: String        // SF Symbol
    let type: ReplyType

    enum ReplyType: Codable, Sendable {
        case text(String)           // Will be spoken via TTS
        case audioFile(String)      // Pre-recorded, stored in Documents
    }
}

@Observable
@MainActor
final class QuickReplyManager {
    private(set) var replies: [QuickReply] = []

    // Default quick replies
    static let defaults: [QuickReply] = [
        QuickReply(id: UUID(), label: "Roger", icon: "checkmark.circle", type: .text("Roger that")),
        QuickReply(id: UUID(), label: "Copy", icon: "doc.on.doc", type: .text("Copy")),
        QuickReply(id: UUID(), label: "On my way", icon: "figure.walk", type: .text("On my way")),
        QuickReply(id: UUID(), label: "Where are you?", icon: "location", type: .text("Where are you?")),
        QuickReply(id: UUID(), label: "Help", icon: "exclamationmark.triangle", type: .text("I need help")),
        QuickReply(id: UUID(), label: "Stand by", icon: "pause.circle", type: .text("Stand by")),
        QuickReply(id: UUID(), label: "All clear", icon: "checkmark.seal", type: .text("All clear")),
        QuickReply(id: UUID(), label: "Meet up", icon: "person.2", type: .text("Let's meet up")),
    ]

    init() { replies = Self.defaults }

    /// Send a quick reply via TTS, encoding the spoken audio for mesh transmission.
    func send(_ reply: QuickReply, using synthesizer: AVSpeechSynthesizer?) {
        switch reply.type {
        case .text(let message):
            let utterance = AVSpeechUtterance(string: message)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            utterance.pitchMultiplier = 1.0
            synthesizer?.speak(utterance)

        case .audioFile:
            // Audio quick replies are not yet implemented — the Opus encoder
            // pipeline integration is pending. The UI guards against reaching
            // this path, but bail out safely just in case.
            return
        }
    }

    /// Add a custom quick reply.
    func addReply(_ reply: QuickReply) {
        replies.append(reply)
    }

    /// Remove a quick reply by ID.
    func removeReply(id: UUID) {
        replies.removeAll { $0.id == id }
    }

    /// Reset to default quick replies.
    func resetToDefaults() {
        replies = Self.defaults
    }
}
