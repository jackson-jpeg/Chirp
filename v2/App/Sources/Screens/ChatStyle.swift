import SwiftUI
import UIKit

// Shared pieces for the Chat and Nearby screens. Their colors live in `Theme`.

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
            Circle().fill(Theme.well(palette))
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
