import SwiftUI
import UIKit

/// Dawn Chorus tokens. Light values are exact from `v2/design/source/*.dc.html`.
/// Dark keeps the same feel at dusk: the same birds and sun, a deep evening
/// sky instead of morning, ink and paper swapped.
enum Theme {
    // Paper and ink
    static let morning = dyn(0xEAF6FC, 0x0D182B)          // screen background
    static let card = dyn(0xFFFFFF, 0x17253D)
    static let ink = dyn(0x14233F, 0xF2F8FC)
    static let inkSecondary = dyn(0x3D5170, 0xA8BBD3)
    static let inkBody = dyn(0x2B3D5C, 0xC7D5E6)
    static let hairline = dyn(0xD6E3EC, 0x2A3B56)
    static let quiet = dyn(0xE3EDF3, 0x22324C)            // quiet chips and wells
    static let sky = dyn(0xCDE9FA, 0x223C63)              // avatar wells, sky chips

    // The one strong button: navy on morning, morning on dusk.
    static let solid = dyn(0x14233F, 0xEAF6FC)
    static let onSolid = dyn(0xFFFFFF, 0x14233F)

    // Sun (talk button, active tab, live states)
    static let sun = Color.hex(0xFFC531)
    static let sunDeep = Color.hex(0xF2A100)
    static let sunRim = Color.hex(0xFFD866)
    static let sunSoft = dyn(0xFFE596, 0x5A4813)          // selected tab pill
    static let sunGlow = dyn(0xFFF1C2, 0x4A3B12)

    // Coral (you are talking, Ping)
    static let coral = Color.hex(0xFF8C69)
    static let coralHot = Color.hex(0xFF6B4A)
    static let coralSoft = dyn(0xFFD6CC, 0x5A2A22)

    // Status
    static let signal = dyn(0x1F8A5B, 0x5BD39A)           // in range, delivered
    static let signalSoft = dyn(0xDDF3E7, 0x163A2A)
    static let danger = dyn(0xB5402A, 0xFF8A70)           // help, block
    static let dangerSoft = dyn(0xFFE8E0, 0x45201A)
    static let link = dyn(0x2F8ED6, 0x6CC0EC)

    // The wire scene
    static let sceneTop = dyn(0x6CC0EC, 0x1B3463)
    static let sceneMid = dyn(0xB4E1F6, 0x3A4F86)
    static let sceneBottom = dyn(0xE3F4FB, 0x5B5F8E)
    static let glowCore = dyn(0xFFF6CF, 0xFFE9B0)
    static let glowEdge = dyn(0xFFE38A, 0xFFC56B)
    static let glowStrength = dynOpacity(1.0, 0.45)
    static let cloud = dyn(0xFFFFFF, 0x8C93BF)
    static let cloudOpacity = dynOpacity(0.8, 0.30)
    static let wire = dyn(0x14233F, 0x0A1222)
    static let chipOnScene = dyn(0xFFFFFF, 0x17253D)

    // Welcome's full-bleed sky: its own stops, ending in `morning` (dark shares the dusk sky).
    static let welcomeSkyTop = dyn(0x5DB8EA, 0x1B3463)
    static let welcomeSkyMid = dyn(0xA3DAF4, 0x3A4F86)

    static let shadow = Color.hex(0x14233F, opacity: 0.10)

    /// Navy in both schemes: ink on the sun, which stays yellow at dusk.
    static let navy = Color.hex(0x14233F)

    // Chat and Nearby (exact from `Chat.dc.html` and `Nearby.dc.html`)
    static let eventPill = dyn(0xD9EEF8, 0x1C2D47)        // "Priya joined the line · 9:41"
    static let field = dyn(0xEEF5F9, 0x22324C)            // the composer's text field
    static let placeholder = dyn(0x7A8BA3, 0x7F93AE)
    static let waveRest = dyn(0xB9CBD8, 0x3E5272)         // unplayed waveform bars
    static let signalText = dyn(0x1F7A50, 0x5BD39A)       // "Direct · strong", heard ticks

    // Status chips (Meet-up, Roll call)
    static let okText = dyn(0x1F6B45, 0x5BD39A)
    static let lateText = dyn(0xA3361F, 0xFF8A70)
    static let pendingFill = dyn(0xEEF1F5, 0x22324C)
    static let turnText = dyn(0x7A5200, 0xFFD866)

    // Lilac (meet-ups)
    static let lilacWell = dyn(0xECE5FF, 0x2C2550)
    static let purple = dyn(0x6A4FD0, 0xB39DF2)
    static let purpleSoft = dyn(0xF0EBFF, 0x2A2347)
    static let flag = Color.hex(0x7D63D6)

    // Find's sun screen
    static let findBackground = dyn(0xFFC531, 0x3A2C08)
    static let findInk = dyn(0x14233F, 0xFFE9A8)
    static let findSecondary = dyn(0x5A3F00, 0xE8C66A)
    static let findButton = dyn(0x14233F, 0xFFE596)
    static let findOnButton = dyn(0xFFFFFF, 0x14233F)

    // Catch up's dark player card
    static let player = dyn(0x14233F, 0x223C63)
    static let playerSecondary = Color.hex(0xC7D6E2)
    static let playerRim = dyn(0x3D5170, 0x5A7396)

    // Meet-up's hill scene
    static let hillTop = dyn(0x6CC0EC, 0x1B3463)
    static let hillBottom = dyn(0xCDEBF8, 0x3A4F86)
    static let farHills = dyn(0xFFFFFF, 0x8C93BF)
    static let gondola = Color.hex(0x3E8CC7)
    static let gondolaWindow = Color.hex(0xCDE9FA)

    /// The round well behind a person's bird (Maya #FFF1C2, Jon #DDF3E7, Priya #ECE5FF).
    static func well(_ p: BirdPalette) -> Color {
        switch p.name {
        case "Yellow": sunGlow
        case "Green": signalSoft
        case "Lilac": lilacWell
        case "Blue": sky
        case "Coral": coralSoft
        case "Teal": dyn(0xC9EFEC, 0x133A38)
        default: dyn(0xFFE3C4, 0x4A3014)
        }
    }

    /// A sender's name over their bubble (Maya #A36A00, Jon #1F7A50, Priya #6A4FD0).
    static func nameColor(_ p: BirdPalette) -> Color {
        switch p.name {
        case "Yellow": dyn(0xA36A00, 0xFFD15C)
        case "Green": signalText
        case "Lilac": dyn(0x6A4FD0, 0xC2B0FF)
        case "Blue": link
        case "Coral": dyn(0xC9533A, 0xFF9C80)
        case "Teal": dyn(0x1B8A84, 0x5FD6CF)
        default: dyn(0xC46A12, 0xFFB870)
        }
    }

    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light) })
    }
    private static func dynOpacity(_ light: Double, _ dark: Double) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: dark) : UIColor(white: 1, alpha: light) })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

/// Nunito, the design's only face, scaled with Dynamic Type from the design's
/// sizes (the files are drawn at the default Large size).
extension Font {
    static func nunito(_ size: CGFloat, _ weight: Font.Weight = .heavy, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Nunito", size: size, relativeTo: style).weight(weight)
    }

    // The design's recurring sizes.
    static let screenTitle = nunito(30, .black, relativeTo: .largeTitle)      // "Ski trip"
    static let pageTitle = nunito(32, .black, relativeTo: .largeTitle)        // "Make your bird"
    static let eyebrow = nunito(13, .black, relativeTo: .caption)             // "JOINING SKI TRIP"
    static let cardTitle = nunito(17, .heavy, relativeTo: .headline)
    static let bodyHeavy = nunito(17, .heavy, relativeTo: .body)
    static let label = nunito(15, .heavy, relativeTo: .subheadline)
    static let meta = nunito(15, .bold, relativeTo: .subheadline)
    static let small = nunito(13, .heavy, relativeTo: .footnote)
    static let tab = nunito(12, .heavy, relativeTo: .caption2)
    static let button = nunito(18, .black, relativeTo: .headline)
}
