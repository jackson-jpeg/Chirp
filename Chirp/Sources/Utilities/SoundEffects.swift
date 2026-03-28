import AudioToolbox
import Foundation

/// Plays short chirp/beep sound effects using system sounds.
/// Does NOT create its own AVAudioEngine — that would conflict with
/// the main AudioEngine's AVAudioSession.
@MainActor
final class SoundEffects {
    static let shared = SoundEffects()

    private init() {}

    // MARK: - Public API

    func playChirpBegin() {
        // System "tink" sound — short, clean, works well for PTT begin
        AudioServicesPlaySystemSound(1057)
    }

    func playChirpEnd() {
        // System "tock" sound
        AudioServicesPlaySystemSound(1105)
    }

    func playPeerJoined() {
        // System positive chime
        AudioServicesPlaySystemSound(1025)
    }

    func playPeerLeft() {
        // System negative tone
        AudioServicesPlaySystemSound(1073)
    }
}
