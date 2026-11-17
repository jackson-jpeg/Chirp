import SwiftUI
import UIKit

/// Tokens the Chat and Nearby files use that `Theme` does not have yet.
/// Light values are exact from `Chat.dc.html` and `Nearby.dc.html`; dark
/// values follow Theme's dusk pattern.
enum ChatStyle {
    /// "Priya joined the line · 9:41" pill (#D9EEF8).
    static let eventPill = dyn(0xD9EEF8, 0x1C2D47)
    /// The composer's text field (#EEF5F9).
    static let field = dyn(0xEEF5F9, 0x22324C)
    /// Unplayed waveform bars (#B9CBD8).
    static let waveRest = dyn(0xB9CBD8, 0x3E5272)
    /// The files' green text: "Direct · strong", the heard ticks, Jon's name (#1F7A50).
    static let signalText = dyn(0x1F7A50, 0x5BD39A)
    /// The text field's placeholder.
    static let placeholder = dyn(0x7A8BA3, 0x7F93AE)

    /// The round well behind a person's bird (Maya #FFF1C2, Jon #DDF3E7, Priya #ECE5FF).
    static func well(_ p: BirdPalette) -> Color {
        switch p.name {
        case "Yellow": Theme.sunGlow
        case "Green": Theme.signalSoft
        case "Lilac": dyn(0xECE5FF, 0x2C2550)
        case "Blue": Theme.sky
        case "Coral": Theme.coralSoft
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
        case "Blue": Theme.link
        case "Coral": dyn(0xC9533A, 0xFF9C80)
        case "Teal": dyn(0x1B8A84, 0x5FD6CF)
        default: dyn(0xC46A12, 0xFFB870)
        }
    }

    /// "Maya", "Maya and Jon", "Maya, Jon and Priya".
    static func names(_ people: [Person]) -> String {
        let n = people.map(\.name)
        switch n.count {
        case 0: return ""
        case 1: return n[0]
        default: return n.dropLast().joined(separator: ", ") + " and " + n[n.count - 1]
        }
    }

    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light) })
    }
}

/// An icon drawn from the design file's own SVG path, in its viewBox units
/// (24 unless given), scaled to the frame it is given.
struct ChatIcon: Shape {
    var box: CGFloat = 24
    var drawn: Path

    init(box: CGFloat = 24, _ build: (inout Path) -> Void) {
        self.box = box
        var p = Path()
        build(&p)
        drawn = p
    }

    func path(in rect: CGRect) -> Path {
        drawn.applying(CGAffineTransform(a: rect.width / box, b: 0, c: 0, d: rect.height / box,
                                         tx: rect.minX, ty: rect.minY))
    }

    /// The files' mic: `rect 8 3 8 12 rx4` and `M5 11a7 7 0 0 0 14 0M12 18v3`.
    static let mic = ChatIcon { p in
        p.addRoundedRect(in: CGRect(x: 8, y: 3, width: 8, height: 12), cornerSize: CGSize(width: 4, height: 4))
        p.move(to: CGPoint(x: 5, y: 11))
        p.addCurve(to: CGPoint(x: 12, y: 18), control1: CGPoint(x: 5, y: 14.87), control2: CGPoint(x: 8.13, y: 18))
        p.addCurve(to: CGPoint(x: 19, y: 11), control1: CGPoint(x: 15.87, y: 18), control2: CGPoint(x: 19, y: 14.87))
        p.move(to: CGPoint(x: 12, y: 18))
        p.addLine(to: CGPoint(x: 12, y: 21))
    }

    /// `M12 19V5M6 11l6-6 6 6`: an arrow pointing up.
    static let arrowUp = ChatIcon { p in
        p.move(to: CGPoint(x: 12, y: 19)); p.addLine(to: CGPoint(x: 12, y: 5))
        p.move(to: CGPoint(x: 6, y: 11)); p.addLine(to: CGPoint(x: 12, y: 5)); p.addLine(to: CGPoint(x: 18, y: 11))
    }
}

/// A person's bird in its round well, placed exactly as the files place it
/// (`translate(origin) scale(scale)` inside a `size` square).
struct ChatWellAvatar: View {
    var palette: BirdPalette
    var size: CGFloat
    var origin: CGPoint
    var scale: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(ChatStyle.well(palette))
            Canvas { ctx, _ in
                BirdRenderer.draw(&ctx, palette: palette, beakOpen: false, center: origin, scale: scale)
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .accessibilityHidden(true)
    }
}

/// The sun fill with the files' `box-shadow: inset 0 -3px 0 #F2A100` lip.
struct ChatSunFill<S: Shape>: View {
    var shape: S
    var top: Color = Theme.sun
    var lip: Color = Theme.sunDeep

    var body: some View {
        shape.fill(lip)
            .overlay { shape.fill(top).offset(y: -3) }
            .clipShape(shape)
    }
}
