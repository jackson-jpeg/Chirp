import SwiftUI
import UIKit

/// Welcome's full-bleed sunrise: two birds on a wire, the yellow one chirping
/// to the coral one, over a bank of clouds that melts into the page. Drawn in
/// `Welcome.dc.html`'s own coordinates (`viewBox="0 40 390 430"`) and scaled to
/// the width it is given.
///
/// It is not a `WireScene`: this file's sky has its own stops and ends in the
/// page color, and its clouds are two layers (a soft white back row and a
/// front row in the page color), which `WireScene` does not draw.
struct WelcomeScene: View {
    static let viewBox = CGRect(x: 0, y: 40, width: 390, height: 430)

    @Environment(\.colorScheme) private var scheme

    // This file's sky (light exact from the design; dark shares the dusk sky
    // of `Theme.sceneTop`/`sceneMid`). It ends in `Theme.morning`, the page.
    private static let skyTop = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: 0x1B3463) : UIColor(rgb: 0x5DB8EA) })
    private static let skyMid = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: 0x3A4F86) : UIColor(rgb: 0xA3DAF4) })

    private static let backClouds: [(CGFloat, CGFloat, CGFloat)] = [
        (20, 430, 50), (90, 414, 46), (160, 436, 50), (240, 418, 46), (310, 432, 50), (380, 416, 46),
    ]
    private static let frontClouds: [(CGFloat, CGFloat, CGFloat)] = [
        (0, 470, 44), (70, 466, 40), (140, 478, 44), (210, 468, 40), (280, 478, 44), (350, 466, 40), (400, 474, 40),
    ]

    var body: some View {
        Canvas { ctx, size in
            let vb = Self.viewBox
            let k = size.width / vb.width
            ctx.scaleBy(x: k, y: k)
            ctx.translateBy(x: -vb.minX, y: -vb.minY)
            let dark = scheme == .dark

            // Sky: <rect width="390" height="470" fill="url(#sky)"/>
            ctx.fill(Path(CGRect(x: 0, y: 0, width: 390, height: 470)), with: .linearGradient(
                Gradient(stops: [.init(color: Self.skyTop, location: 0),
                                 .init(color: Self.skyMid, location: 0.65),
                                 .init(color: Theme.morning, location: 1)]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: 470)))

            // Sun: <circle cx="195" cy="170" r="170" fill="url(#sun)"/>
            let sunCenter = CGPoint(x: 195, y: 170)
            let sunR: CGFloat = 170
            ctx.opacity = dark ? 0.45 : 1
            ctx.fill(Path(ellipseIn: CGRect(x: sunCenter.x - sunR, y: sunCenter.y - sunR, width: sunR * 2, height: sunR * 2)),
                     with: .radialGradient(Gradient(stops: [.init(color: Theme.glowCore, location: 0),
                                                           .init(color: Theme.glowEdge, location: 0.5),
                                                           .init(color: Theme.glowEdge.opacity(0), location: 1)]),
                                           center: sunCenter, startRadius: 0, endRadius: sunR))
            ctx.opacity = 1

            // Clouds: a soft back row, then a front row in the page color.
            for (x, y, r) in Self.backClouds {
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(Theme.cloud.opacity(dark ? 0.30 : 0.55)))
            }
            for (x, y, r) in Self.frontClouds {
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(Theme.morning))
            }

            // Wire: M-10 322 Q 195 352 400 318, 5 wide.
            var wire = Path()
            wire.move(to: CGPoint(x: -10, y: 322))
            wire.addQuadCurve(to: CGPoint(x: 400, y: 318), control: CGPoint(x: 195, y: 352))
            ctx.stroke(wire, with: .color(Theme.wire), style: StrokeStyle(lineWidth: 5, lineCap: .round))

            // The yellow bird chirping, the coral one listening (facing left).
            BirdRenderer.draw(&ctx, palette: .yellow, beakOpen: true,
                              center: CGPoint(x: 100, y: 268), scale: 0.5)
            BirdRenderer.draw(&ctx, palette: .coral, beakOpen: false,
                              center: CGPoint(x: 298, y: 266), scale: 0.5, facingLeft: true)

            // The chirp: two arcs, 6 wide.
            var arcs = WireScene.arc(190, 206, 198, 198, 198, 186, 190, 178)
            arcs.addPath(WireScene.arc(205, 214, 219, 198, 219, 174, 205, 158))
            ctx.stroke(arcs, with: .color(dark ? Color.white.opacity(0.9) : BirdRenderer.ink),
                       style: StrokeStyle(lineWidth: 6, lineCap: .round))
        }
        .aspectRatio(Self.viewBox.width / Self.viewBox.height, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Two birds on a wire at sunrise, one chirping to the other")
        .accessibilityAddTraits(.isImage)
    }
}
