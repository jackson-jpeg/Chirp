@preconcurrency import AVFoundation
import ChirpCore
import UIKit

/// Plays the birds' chirps (ChirpCore `ChirpSound`): a preview in Make your
/// bird, a friend's chirp when they start talking, and a ping.
///
/// It opens no audio session of its own (2.5.4: nothing at launch). With
/// Talk's session open it plays through it; otherwise through the app's
/// default session, which follows the silent switch, so a ping also buzzes.
@MainActor
enum ChirpPlayer {
    private static var players: [Int: AVAudioPlayer] = [:]

    static func play(_ chirp: Int, loud: Bool = false) {
        let n = max(0, min(Int(Bird.chirpCount) - 1, chirp))
        guard let player = player(n) else { return }
        player.volume = loud ? 1 : 0.6
        player.currentTime = 0
        player.play()
    }

    /// A friend pinged you: their chirp twice, loud, and a strong buzz.
    static func ping(_ chirp: Int) {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        play(chirp, loud: true)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(550))
            play(chirp, loud: true)
        }
    }

    private static func player(_ n: Int) -> AVAudioPlayer? {
        if let p = players[n] { return p }
        let p = try? AVAudioPlayer(data: ChirpSound.wav(n), fileTypeHint: AVFileType.wav.rawValue)
        p?.prepareToPlay()
        players[n] = p
        return p
    }
}
