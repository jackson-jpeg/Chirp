import SwiftUI

/// Welcome's full-bleed sunrise: two birds on a wire, the yellow one chirping
/// to the coral one, over a bank of clouds that melts into the page. Drawn in
/// `Welcome.dc.html`'s own coordinates (`viewBox="0 40 390 430"`) and scaled to
/// the width it is given.
///
/// It is not a `WireScene`: this file's sky has its own stops and ends in the
/// page color, and its clouds are two layers (a soft white back row and a
/// front row in the page color). It composes the same `SceneDrawing` steps.
struct WelcomeScene: View {
    static let viewBox = CGRect(x: 0, y: 40, width: 390, height: 430)

    @Environment(\.colorScheme) private var scheme

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

            // Sky: <rect width="390" height="470" fill="url(#sky)"/>, ending in the page color.
            SceneDrawing.sky(&ctx, CGRect(x: 0, y: 0, width: 390, height: 470),
                             stops: [.init(color: Theme.welcomeSkyTop, location: 0),
                                     .init(color: Theme.welcomeSkyMid, location: 0.65),
                                     .init(color: Theme.morning, location: 1)])

            // Sun: <circle cx="195" cy="170" r="170" fill="url(#sun)"/>
            SceneDrawing.glow(&ctx, center: CGPoint(x: 195, y: 170), radius: 170, edge: 1, dark: dark)

            // Clouds: a soft back row, then a front row in the page color.
            SceneDrawing.clouds(&ctx, Self.backClouds, opacity: 0.55, dark: dark)
            SceneDrawing.clouds(&ctx, Self.frontClouds, color: Theme.morning, dark: dark)

            // Wire: M-10 322 Q 195 352 400 318, 5 wide.
            SceneDrawing.wire(&ctx, from: CGPoint(x: -10, y: 322), control: CGPoint(x: 195, y: 352),
                              to: CGPoint(x: 400, y: 318), width: 5)

            // The yellow bird chirping, the coral one listening (facing left).
            BirdRenderer.draw(&ctx, palette: .yellow, beakOpen: true,
                              center: CGPoint(x: 100, y: 268), scale: 0.5)
            BirdRenderer.draw(&ctx, palette: .coral, beakOpen: false,
                              center: CGPoint(x: 298, y: 266), scale: 0.5, facingLeft: true)

            // The chirp: two arcs, 6 wide.
            var arcs = SceneDrawing.arc(190, 206, 198, 198, 198, 186, 190, 178)
            arcs.addPath(SceneDrawing.arc(205, 214, 219, 198, 219, 174, 205, 158))
            SceneDrawing.chirp(&ctx, arcs, width: 6, dark: dark)
        }
        .aspectRatio(Self.viewBox.width / Self.viewBox.height, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Two birds on a wire at sunrise, one chirping to the other")
        .accessibilityAddTraits(.isImage)
    }
}
