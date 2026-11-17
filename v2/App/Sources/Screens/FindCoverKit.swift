import SwiftUI
import UIKit

// Small shared pieces for the four covers over the tabs (Find, Meetup,
// RollCall, CatchUp). Named `Cover*` so they cannot collide with the shared kit.

/// Colors the four cover designs use that `Theme` has no token for. Light
/// values are exact from the .dc.html files; dark keeps the same feel.
enum CoverTokens {
    // Find's sun screen
    static let findBackground = dyn(0xFFC531, 0x3A2C08)
    static let findInk = dyn(0x14233F, 0xFFE9A8)
    static let findSecondary = dyn(0x5A3F00, 0xE8C66A)
    static let findButton = dyn(0x14233F, 0xFFE596)
    static let findOnButton = dyn(0xFFFFFF, 0x14233F)

    // Lilac (meet-ups)
    static let lilacWell = dyn(0xECE5FF, 0x2E2650)
    static let purple = dyn(0x6A4FD0, 0xB39DF2)
    static let purpleSoft = dyn(0xF0EBFF, 0x2A2347)
    static let flag = Color.hex(0x7D63D6)

    // Status chips
    static let okText = dyn(0x1F6B45, 0x5BD39A)
    static let lateText = dyn(0xA3361F, 0xFF8A70)
    static let pendingFill = dyn(0xEEF1F5, 0x22324C)
    static let turnText = dyn(0x7A5200, 0xFFD866)

    // Catch up's dark player card
    static let player = dyn(0x14233F, 0x223C63)
    static let playerSecondary = dyn(0xC7D6E2, 0xC7D6E2)
    static let playerRim = dyn(0x3D5170, 0x5A7396)

    // Meet-up hill scene
    static let hillTop = dyn(0x6CC0EC, 0x1B3463)
    static let hillBottom = dyn(0xCDEBF8, 0x3A4F86)
    static let farHills = dyn(0xFFFFFF, 0x8C93BF)
    static let gondola = Color.hex(0x3E8CC7)
    static let gondolaWindow = Color.hex(0xCDE9FA)

    /// The avatar well behind each palette, as the files color them.
    static func well(for palette: BirdPalette) -> Color {
        switch palette.name {
        case "Green": return Theme.signalSoft
        case "Yellow": return Theme.sunGlow
        case "Lilac": return lilacWell
        case "Coral": return Theme.coralSoft
        default: return Theme.sky
        }
    }

    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light) })
    }
}

/// A bird drawn at the file's own `translate(cx cy) scale(s)` inside a box of
/// `size`. The tail may poke past the box, as it does in the files.
/// `showLegs: false` hides the legs for files whose symbol has none.
struct CoverBirdCanvas: View {
    var palette: BirdPalette
    var size: CGSize
    var center: CGPoint
    var scale: CGFloat
    var showLegs = true

    private let bleed: CGFloat = 12

    var body: some View {
        Canvas { ctx, _ in
            ctx.translateBy(x: bleed, y: bleed)
            if !showLegs {
                ctx.clip(to: Path(CGRect(x: -bleed, y: -bleed, width: size.width + 2 * bleed,
                                         height: center.y + 99 * scale + bleed)))
            }
            BirdRenderer.draw(&ctx, palette: palette, beakOpen: false, center: center, scale: scale)
        }
        .frame(width: size.width + 2 * bleed, height: size.height + 2 * bleed)
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}

/// A round avatar: the palette's well and the bird at the file's transform.
struct CoverBirdDisc: View {
    var palette: BirdPalette
    var diameter: CGFloat
    var center: CGPoint
    var scale: CGFloat
    var well: Color? = nil

    var body: some View {
        ZStack {
            Circle().fill(well ?? CoverTokens.well(for: palette))
            CoverBirdCanvas(palette: palette, size: CGSize(width: diameter, height: diameter),
                            center: center, scale: scale, showLegs: false)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

/// "< Chat", "< Talk": the files' plain back control (16 pt heavy, 44 pt tall).
struct CoverBackButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 20, height: 20)
                Text(title).font(.nunito(16, .heavy, relativeTo: .body))
            }
            .foregroundStyle(Theme.ink)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to \(title)")
    }
}

/// The round 44 pt close control (Find's "Stop finding").
struct CoverCloseButton: View {
    var label: String
    var tint: Color = Theme.ink
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// A small rounded status chip ("There", "OK · 10:12").
struct CoverChip: View {
    var text: String
    var fill: Color
    var foreground: Color
    var verticalPadding: CGFloat = 4
    var cornerRadius: CGFloat = 12

    var body: some View {
        Text(text)
            .font(.nunito(13, .black, relativeTo: .footnote))
            .foregroundStyle(foreground)
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, 10)
            .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
