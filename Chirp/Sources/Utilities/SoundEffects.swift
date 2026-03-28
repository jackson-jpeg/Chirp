import AudioToolbox
import Foundation

/// Plays short sound effects using system sounds.
/// NEVER creates its own AVAudioEngine — avoids conflicts with the
/// main AudioEngine's audio session.
@MainActor
final class SoundEffects {
    static let shared = SoundEffects()

    private init() {}

    // MARK: - PTT Sounds

    /// Short click for PTT begin — system keyboard click
    func playChirpBegin() {
        AudioServicesPlaySystemSound(1104) // System click
    }

    /// Short tick for PTT end
    func playChirpEnd() {
        AudioServicesPlaySystemSound(1105) // System tock
    }

    /// Peer connected chime
    func playPeerJoined() {
        AudioServicesPlaySystemSound(1025)
    }

    /// Peer disconnected tone
    func playPeerLeft() {
        AudioServicesPlaySystemSound(1073)
    }
}
