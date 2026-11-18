import Foundation

/// What Big Birdhouse, the one purchase, adds (Jackson, Inbox chirp-2-0-revenue-shape,
/// "softer"; docs/proposals/revenue-2.0.md):
///
/// - Private birdhouses are free up to `freeBirds` birds. Big Birdhouse lets a birdhouse
///   you started grow past that.
/// - Every bird color and every chirp (free: the four colors of the app icon's
///   birds and two chirps).
///
/// Free for everyone, always: joining any birdhouse, carrying everyone's messages,
/// talking and texting, captions, Block, roll call and help, check-in, Find,
/// Ping, Demo Mode. Joiners never pay, and nothing ever stops working mid-trip:
/// the cap is counted on the starter's phone and only asks before the starter
/// invites more people. With no servers it is soft, and that is accepted.
public enum BigBirdhouse {
    public static let freeBirds = 4
    /// Indices into the app's `BirdPalette.all` (Blue, Teal, Yellow, Coral,
    /// Green, Lilac, Orange): Blue, Yellow, Coral and Green are free.
    public static let freePalettes: Set<Int> = [0, 2, 3, 4]
    /// Indices into `ChirpSound.names` (Finch, Robin, Wren).
    public static let freeChirps: Set<Int> = [0, 1]

    /// Birds in a birdhouse as this phone sees it: me plus everyone proved on it.
    public static func birds(members: Int) -> Int { members + 1 }

    public static func paletteIsFree(_ index: Int) -> Bool { freePalettes.contains(index) }
    public static func chirpIsFree(_ index: Int) -> Bool { freeChirps.contains(index) }

    public enum Invite: Equatable, Sendable {
        /// Share the link.
        case share
        /// The starter of a free birdhouse that is already full: offer Big Birdhouse
        /// first (they can still say Not now; nothing is cut off).
        case offerBigBirdhouse
    }

    /// What "Invite friends" does. Only the starter is asked: joiners never see
    /// a price, so a joiner's invite always shares.
    public static func invite(birds: Int, startedByMe: Bool, unlocked: Bool) -> Invite {
        guard startedByMe, !unlocked, birds >= freeBirds else { return .share }
        return .offerBigBirdhouse
    }

    /// Whether the starter sees "Your birdhouse has N birds" on Talk: their free
    /// birdhouse has grown past the cap anyway (someone else shared the link), and
    /// they have not put the card away at this size or larger.
    public static func showsCard(birds: Int, startedByMe: Bool, unlocked: Bool, dismissedAt: Int?) -> Bool {
        guard startedByMe, !unlocked, birds > freeBirds else { return false }
        if let d = dismissedAt, birds <= d { return false }
        return true
    }

    /// A saved choice that is no longer allowed (a refund) falls back to the
    /// first free one, so a bird never wears what it does not own.
    public static func allowedPalette(_ index: Int, unlocked: Bool) -> Int {
        unlocked || paletteIsFree(index) ? index : freePalettes.min()!
    }

    public static func allowedChirp(_ index: Int, unlocked: Bool) -> Int {
        unlocked || chirpIsFree(index) ? index : freeChirps.min()!
    }
}
