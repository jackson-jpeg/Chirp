import ActivityKit
import ChirpCore
import Foundation

/// The Lock Screen and Dynamic Island card (item 7). Shared by the app, which
/// starts and updates it, and the `ChirpLive` widget extension, which draws it.
/// Its state is ChirpCore's `LiveCard`, where the rules and tests live.
struct ChirpActivity: ActivityAttributes {
    typealias ContentState = LiveCard
    /// The flock this card follows.
    var flockID: String
}

enum ChirpLinks {
    /// The card's button: opens the app on Talk. Nothing on the card works
    /// while the phone is locked (voice never runs in the background, 2.5.4).
    static let talk = URL(string: "chirpchirps://talk")!
}
