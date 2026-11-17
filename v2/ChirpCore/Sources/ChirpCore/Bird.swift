import Foundation

/// Each person's bird (scope item 6): a color palette and a start-talking
/// chirp, each chosen from a fixed set that ships in the app.
///
/// Carried as two indices in the signed presence, never as colors or audio:
/// a peer cannot push arbitrary sound or an unreadable color pair onto
/// someone else's phone. The set is the approved Dawn Chorus design
/// (`v2/design/source/MakeBird.dc.html`): seven feather colors (blue, teal,
/// yellow, coral, green, lilac, orange, in that order) and three chirps
/// (Finch, Robin, Wren). The app maps each index to its colors and sound.
public struct Bird: Equatable, Hashable, Sendable {
    public static let paletteCount: UInt8 = 7
    public static let chirpCount: UInt8 = 3
    public static let `default` = Bird(palette: 0, chirp: 0)!

    public let palette: UInt8
    public let chirp: UInt8

    /// Nil for an index outside the shipped set (a newer or hostile peer).
    public init?(palette: UInt8, chirp: UInt8) {
        guard palette < Self.paletteCount, chirp < Self.chirpCount else { return nil }
        self.palette = palette
        self.chirp = chirp
    }

    /// A starting bird for someone who has not picked one, spread by PeerID so
    /// two people nearby rarely start out the same.
    public static func suggested(for peer: PeerID) -> Bird {
        let b = [UInt8](peer.bytes)
        return Bird(palette: b[0] % paletteCount, chirp: b[1] % chirpCount)!
    }
}
