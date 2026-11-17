import SwiftUI

/// The Talk screen's wire scene, drawn in the design's 358 x 214 space
/// (`Talk-Listen.dc.html` / `Talk-Hold.dc.html`).
///
/// It is its own Canvas rather than `WireScene` because the Hold file draws
/// the "you are heard" ripples *behind* the wire and birds, and its name chips
/// carry a check mark with left-aligned text; `WireScene` draws arcs on top
/// and centres plain chips. The sky, glow and clouds are drawn exactly as
/// `WireScene` draws them.
struct TalkScene: View {
    enum Mode: Equatable { case listening, holding, quiet }

    var mode: Mode
    /// Up to three people on the wire, the one with the line first.
    var birds: [Person]

    @Environment(\.colorScheme) private var scheme

    nonisolated static let designSize = CGSize(width: 358, height: 214)

    var body: some View {
        let mode = mode
        let birds = Array(birds.prefix(3))
        let dark = scheme == .dark
        Canvas { ctx, size in
            let k = size.width / TalkScene.designSize.width
            ctx.scaleBy(x: k, y: k)
            TalkSceneDrawing.sky(&ctx, clouds: mode != .holding, dark: dark)
            if mode == .holding { TalkSceneDrawing.ripples(&ctx, dark: dark) }
            TalkSceneDrawing.wire(&ctx)
            for (i, person) in birds.enumerated() {
                let slot = TalkSceneDrawing.slots[i]
                let facingLeft = mode == .holding ? i == 2 : i > 0
                BirdRenderer.draw(&ctx, palette: person.palette, beakOpen: mode == .listening && i == 0,
                                  center: CGPoint(x: slot.x, y: slot.y), scale: slot.scale, facingLeft: facingLeft)
            }
            if mode == .listening, !birds.isEmpty { TalkSceneDrawing.talkerArcs(&ctx) }
            for (i, person) in birds.enumerated() {
                if mode == .holding {
                    TalkSceneDrawing.heardChip(&ctx, name: person.name, slot: i)
                } else {
                    TalkSceneDrawing.plainChip(&ctx, name: person.name, slot: i, strong: mode == .listening && i == 0)
                }
            }
        }
        .aspectRatio(TalkScene.designSize.width / TalkScene.designSize.height, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(Self.label(mode: mode, names: birds.prefix(3).map(\.name)))
        .accessibilityAddTraits(.isImage)
    }

    /// The files' aria-labels, built from the flock.
    static func label(mode: Mode, names: [String]) -> String {
        guard !names.isEmpty else { return "No one else is on the wire yet." }
        let list = TalkText.list(names)
        switch mode {
        case .listening: return "\(list) on the wire. \(names[0]) is talking."
        case .holding: return names.count == 1 ? "\(list) is hearing you." : "\(list) are all hearing you."
        case .quiet: return "\(list) on the wire. The line is quiet."
        }
    }
}

enum TalkText {
    /// "Maya, Jon and Priya".
    static func list(_ names: [String]) -> String {
        guard let last = names.last else { return "" }
        if names.count == 1 { return last }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }
}

/// Drawing steps in the scene's design coordinates.
enum TalkSceneDrawing {
    /// Where the files sit the three birds: `translate(x y) scale(s)`.
    static let slots: [(x: CGFloat, y: CGFloat, scale: CGFloat)] = [(70, 127, 0.27), (190, 133, 0.26), (292, 125, 0.26)]

    /// Chip widths the files use for the demo names (Listen, Hold); other
    /// names are measured.
    private static let designChipWidths: [String: (listen: CGFloat, hold: CGFloat)] = [
        "Maya": (64, 76), "Jon": (48, 64), "Priya": (56, 72),
    ]

    static func sky(_ ctx: inout GraphicsContext, clouds: Bool, dark: Bool) {
        let size = TalkScene.designSize
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(stops: [.init(color: Theme.sceneTop, location: 0), .init(color: Theme.sceneMid, location: 0.7),
                             .init(color: Theme.sceneBottom, location: 1)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        // <circle cx="70" cy="60" r="120" fill="url(#glow)"/>
        let c = CGPoint(x: 70, y: 60), r: CGFloat = 120
        var g = ctx
        g.opacity = dark ? 0.45 : 1
        g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
               with: .radialGradient(Gradient(stops: [.init(color: Theme.glowCore, location: 0),
                                                     .init(color: Theme.glowEdge.opacity(0.9), location: 0.5),
                                                     .init(color: Theme.glowEdge.opacity(0), location: 1)]),
                                     center: c, startRadius: 0, endRadius: r))
        guard clouds else { return }
        let puffs: [(CGFloat, CGFloat, CGFloat)] = [(20, 214, 34), (70, 222, 30), (130, 216, 34), (190, 224, 30),
                                                    (250, 214, 34), (310, 222, 30), (360, 214, 30)]
        for (x, y, r) in puffs {
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                     with: .color(Theme.cloud.opacity(dark ? 0.30 : 0.8)))
        }
    }

    /// Hold: three white half rings rising from the bottom centre, behind the wire.
    static func ripples(_ ctx: inout GraphicsContext, dark: Bool) {
        let rings: [(r: CGFloat, w: CGFloat, o: Double)] = [(70, 4, 0.9), (110, 3.5, 0.6), (150, 3, 0.35)]
        let c = CGPoint(x: 179, y: 214)
        for ring in rings {
            // A full circle; its lower half falls outside the scene and is clipped.
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - ring.r, y: c.y - ring.r, width: ring.r * 2, height: ring.r * 2)),
                       with: .color(Color.white.opacity(ring.o * (dark ? 0.6 : 1))),
                       style: .init(lineWidth: ring.w, lineCap: .round))
        }
    }

    /// An arc from the files' `M x0 y0 C c1 c2 x1 y1` form (same as
    /// `WireScene.arc`, which is main-actor isolated as a View member).
    static func arc(_ x0: CGFloat, _ y0: CGFloat, _ c1x: CGFloat, _ c1y: CGFloat, _ c2x: CGFloat, _ c2y: CGFloat,
                    _ x1: CGFloat, _ y1: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x0, y: y0))
        p.addCurve(to: CGPoint(x: x1, y: y1), control1: CGPoint(x: c1x, y: c1y), control2: CGPoint(x: c2x, y: c2y))
        return p
    }

    /// `M-4 150 Q 179 186 362 144`, 3.5 wide.
    static func wire(_ ctx: inout GraphicsContext) {
        var w = Path()
        w.move(to: CGPoint(x: -4, y: 150))
        w.addQuadCurve(to: CGPoint(x: 362, y: 144), control: CGPoint(x: 179, y: 186))
        ctx.stroke(w, with: .color(Theme.wire), style: .init(lineWidth: 3.5, lineCap: .round))
    }

    /// The `)))` in front of the talker in the first slot.
    static func talkerArcs(_ ctx: inout GraphicsContext) {
        let p = Path { p in
            p.addPath(TalkSceneDrawing.arc(121, 104, 125, 100, 125, 94, 121, 90))
            p.addPath(TalkSceneDrawing.arc(129, 110, 137, 101, 137, 87, 129, 78))
        }
        ctx.stroke(p, with: .color(Theme.ink), style: .init(lineWidth: 3, lineCap: .round))
    }

    private static func chipText(_ ctx: GraphicsContext, _ name: String, color: Color) -> GraphicsContext.ResolvedText {
        ctx.resolve(Text(name).font(.custom("Nunito", fixedSize: 12.5).weight(.black)).foregroundStyle(color))
    }

    /// Listen and quiet: a centred name under each bird; the talker's is navy.
    static func plainChip(_ ctx: inout GraphicsContext, name: String, slot: Int, strong: Bool) {
        let text = chipText(ctx, name, color: strong ? Theme.onSolid : Theme.ink)
        let width = designChipWidths[name]?.listen ?? (text.measure(in: CGSize(width: 200, height: 40)).width.rounded(.up) + 28)
        let x = slots[slot].x
        let rect = CGRect(x: x - width / 2, y: 176, width: width, height: 24)
        ctx.fill(Path(roundedRect: rect, cornerRadius: 12), with: .color(strong ? Theme.solid : Theme.chipOnScene))
        ctx.draw(text, at: CGPoint(x: x, y: 188), anchor: .center)
    }

    /// Hold: a green check and the name, "they hear you".
    static func heardChip(_ ctx: inout GraphicsContext, name: String, slot: Int) {
        let text = chipText(ctx, name, color: Theme.ink)
        let width = designChipWidths[name]?.hold ?? (text.measure(in: CGSize(width: 200, height: 40)).width.rounded(.up) + 42)
        // The files centre these chips on 70, 188 and 290 (bird x, then 2 pt left).
        let cx = slots[slot].x - (slot == 0 ? 0 : 2)
        let rect = CGRect(x: cx - width / 2, y: 176, width: width, height: 24)
        ctx.fill(Path(roundedRect: rect, cornerRadius: 12), with: .color(Theme.chipOnScene))
        var check = Path()
        check.move(to: CGPoint(x: rect.minX + 10, y: 188))
        check.addLine(to: CGPoint(x: rect.minX + 14, y: 192))
        check.addLine(to: CGPoint(x: rect.minX + 22, y: 184))
        ctx.stroke(check, with: .color(Theme.signal), style: .init(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
        ctx.draw(text, at: CGPoint(x: rect.minX + 28, y: 188), anchor: .leading)
    }
}
