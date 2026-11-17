import SwiftUI

// MARK: - The wire scene

/// A bird on the wire, in the scene's design coordinates (the `translate` and
/// `scale` of its `<g>` in the .dc.html file).
struct SceneBird: Identifiable {
    let id = UUID()
    var palette: BirdPalette
    var center: CGPoint
    var scale: CGFloat
    var facingLeft = false
    var talking = false
}

/// The sky card that heads Talk, Make your bird, Welcome and others: a dawn
/// gradient, the sun's glow, clouds, one wire and the birds on it. Everything is
/// laid out in the design's own coordinate space (`designSize`) and scaled to
/// the width the view is given, so it matches the files at any phone width.
struct WireScene: View {
    var designSize: CGSize
    /// The wire as the files draw it: `M start Q control end`.
    var wire: (start: CGPoint, control: CGPoint, end: CGPoint)
    var wireWidth: CGFloat = 3.5
    var glow: (center: CGPoint, radius: CGFloat)
    var clouds: [(CGPoint, CGFloat)] = []
    var birds: [SceneBird]
    /// Sound arcs in front of a talker: two quadratic-ish arcs, as in the files.
    var arcs: [Path] = []
    var arcWidth: CGFloat = 3
    /// Text chips under the birds (name labels); `strong` is the talker's.
    var chips: [(center: CGPoint, width: CGFloat, text: String, strong: Bool)] = []

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { ctx, size in
            let k = size.width / designSize.width
            ctx.scaleBy(x: k, y: k)
            let rect = CGRect(origin: .zero, size: designSize)
            ctx.fill(Path(rect), with: .linearGradient(
                Gradient(stops: [.init(color: Theme.sceneTop, location: 0), .init(color: Theme.sceneMid, location: 0.7),
                                 .init(color: Theme.sceneBottom, location: 1)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: designSize.height)))
            let g = glow
            ctx.opacity = scheme == .dark ? 0.45 : 1
            ctx.fill(Path(ellipseIn: CGRect(x: g.center.x - g.radius, y: g.center.y - g.radius, width: g.radius * 2, height: g.radius * 2)),
                     with: .radialGradient(Gradient(stops: [.init(color: Theme.glowCore, location: 0),
                                                           .init(color: Theme.glowEdge.opacity(0.9), location: 0.5),
                                                           .init(color: Theme.glowEdge.opacity(0), location: 1)]),
                                           center: g.center, startRadius: 0, endRadius: g.radius))
            ctx.opacity = 1
            for (c, r) in clouds {
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .color(Theme.cloud.opacity(scheme == .dark ? 0.30 : 0.8)))
            }
            var w = Path()
            w.move(to: wire.start); w.addQuadCurve(to: wire.end, control: wire.control)
            ctx.stroke(w, with: .color(Theme.wire), style: .init(lineWidth: wireWidth, lineCap: .round))
            for b in birds {
                BirdRenderer.draw(&ctx, palette: b.palette, beakOpen: b.talking, center: b.center, scale: b.scale, facingLeft: b.facingLeft)
            }
            for a in arcs {
                ctx.stroke(a, with: .color(scheme == .dark ? Color.white.opacity(0.9) : BirdRenderer.ink),
                           style: .init(lineWidth: arcWidth, lineCap: .round))
            }
            for chip in chips {
                let r = CGRect(x: chip.center.x - chip.width / 2, y: chip.center.y - 12, width: chip.width, height: 24)
                ctx.fill(Path(roundedRect: r, cornerRadius: 12),
                         with: .color(chip.strong ? Color.hex(0x14233F) : Theme.chipOnScene))
                ctx.draw(Text(chip.text).font(.custom("Nunito", fixedSize: 12.5).weight(.black))
                            .foregroundStyle(chip.strong ? Color.white : Theme.ink),
                         at: CGPoint(x: chip.center.x, y: chip.center.y))
            }
        }
        .aspectRatio(designSize.width / designSize.height, contentMode: .fit)
    }

    /// An arc from the files' `M x0 y0 C c1 c2 x1 y1` form.
    static func arc(_ x0: CGFloat, _ y0: CGFloat, _ c1x: CGFloat, _ c1y: CGFloat, _ c2x: CGFloat, _ c2y: CGFloat,
                    _ x1: CGFloat, _ y1: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x0, y: y0))
        p.addCurve(to: CGPoint(x: x1, y: y1), control1: CGPoint(x: c1x, y: c1y), control2: CGPoint(x: c2x, y: c2y))
        return p
    }
}

/// The scene card's frame: 28 pt corners and the files' soft two-layer shadow.
struct SceneCard<Content: View>: View {
    var cornerRadius: CGFloat = 28
    @ViewBuilder var content: Content
    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Theme.shadow.opacity(0.6), radius: 0, y: 1)
            .shadow(color: Theme.shadow, radius: 15, y: 10)
    }
}

// MARK: - Cards and buttons

/// White rounded card (20 pt corners, 16 pt padding), the files' main container.
struct Card<Content: View>: View {
    var padding: EdgeInsets = .init(top: 14, leading: 16, bottom: 16, trailing: 16)
    var cornerRadius: CGFloat = 20
    var fill: Color = Theme.card
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// The 56 pt pill: "Hop on the line", "Start a flock".
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.button)
            .foregroundStyle(Theme.onSolid)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.solid, in: Capsule())
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.85 : 1)
    }
}

/// The outlined pill: "Join one nearby".
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.button)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.solid, lineWidth: 2))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// A 44 pt choice pill (chirps, RSVP): filled when selected.
struct ChoicePill: View {
    var title: String
    var systemImage: String? = nil
    var selected: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 11, weight: .black)) }
                Text(title)
            }
            .font(.label.weight(.black))
            .foregroundStyle(selected ? Theme.onSolid : Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(selected ? Theme.solid : Theme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Theme.solid : Theme.hairline, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// "JOINING SKI TRIP": 13 pt black, tracked, uppercase.
struct Eyebrow: View {
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(.eyebrow)
            .tracking(1.3)
            .foregroundStyle(Theme.inkSecondary)
    }
}

/// A round bird avatar on a sky well with a white ring (the header's "You").
struct BirdAvatar: View {
    var palette: BirdPalette
    var size: CGFloat = 44
    var talking = false
    var ring: CGFloat = 3
    var body: some View {
        ZStack {
            Circle().fill(Theme.sky)
            BirdView(palette: palette, talking: talking)
                .padding(size * 0.12)
                .offset(x: -size * 0.06, y: size * 0.04)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.card, lineWidth: ring))
        .shadow(color: Theme.shadow.opacity(1.5), radius: 4, y: 2)
    }
}

/// Four rising bars: how well the line is heard (green), like the Talk header.
struct LineBars: View {
    var level: Int = 4
    var color: Color = Theme.signal
    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(0..<4) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < level ? color : Theme.hairline)
                    .frame(width: 3.5, height: CGFloat(5 + i * 3))
            }
        }
        .frame(height: 14, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// The voice level meter from the caption card (bars played in sun, the rest quiet).
struct VoiceMeter: View {
    var heights: [CGFloat] = [6, 12, 18, 10, 16, 8, 14, 6, 10, 6, 4]
    var played: Int = 7
    var color: Color = Theme.sunDeep
    var body: some View {
        HStack(spacing: 3) {
            ForEach(heights.indices, id: \.self) { i in
                Capsule().fill(i < played ? color : Theme.hairline).frame(width: 4, height: heights[i])
            }
        }
        .frame(height: 20)
        .accessibilityHidden(true)
    }
}

extension View {
    /// The files' screen padding and background.
    func screenBackground() -> some View {
        background(Theme.morning.ignoresSafeArea())
    }
}
