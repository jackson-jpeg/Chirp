import SwiftUI

/// The big talk button as the files draw it: a 176 pt white disc around a
/// 144 pt sun disc (6 pt rim ring inside, and a sunDeep lip: 8 pt at the
/// bottom at rest, pressed in to 4 pt at the top while held), your bird inside.
/// Held, it gets the coral ring (8 pt coralSoft, 1 pt coral) and a closer shadow.
/// Purely visual: TalkView owns the gesture and accessibility.
struct TalkButtonFace: View {
    var talking: Bool
    var palette: BirdPalette

    var body: some View {
        ZStack {
            if talking {
                Circle().fill(Theme.coral).frame(width: 194, height: 194)
                Circle().fill(Theme.coralSoft).frame(width: 192, height: 192)
            }
            Circle()
                .fill(Theme.card)
                .shadow(color: talking ? .clear : Color.hex(0x14233F, opacity: 0.06), radius: 0, y: 2)
                .shadow(color: talking ? Color.hex(0x14233F, opacity: 0.12) : Color.hex(0x14233F, opacity: 0.16),
                        radius: talking ? 8 : 20, y: talking ? 6 : 18)
                .frame(width: 176, height: 176)
            ZStack {
                Circle().fill(Theme.sunRim)
                Circle().fill(Theme.sun).padding(6)
                TalkLipShape(dy: talking ? 4 : -8).fill(Theme.sunDeep, style: FillStyle(eoFill: true))
            }
            .frame(width: 144, height: 144)
            .clipShape(Circle())
            TalkButtonBird(palette: palette, talking: talking)
                .frame(width: 112, height: 96)
        }
        .frame(width: 176, height: 176)
        .accessibilityHidden(true)
    }
}

/// CSS `inset 0 dy 0 color`: the disc minus itself shifted by `dy`
/// (the part outside the disc is clipped away by the caller).
struct TalkLipShape: Shape {
    var dy: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: rect)
        p.addEllipse(in: rect.offsetBy(dx: 0, dy: dy))
        return p
    }
}

/// The 112 x 96 bird box inside the button: `translate(54 50) scale(0.3)` at
/// rest, `translate(50 52) scale(0.3)` with the beak open and two arcs held.
struct TalkButtonBird: View {
    var palette: BirdPalette
    var talking: Bool

    var body: some View {
        let palette = palette
        let talking = talking
        Canvas { ctx, size in
            ctx.scaleBy(x: size.width / 112, y: size.height / 96)
            BirdRenderer.draw(&ctx, palette: palette, beakOpen: talking,
                              center: talking ? CGPoint(x: 50, y: 52) : CGPoint(x: 54, y: 50), scale: 0.3)
            if talking {
                let arcs = Path { p in
                    p.addPath(TalkSceneDrawing.arc(100, 30, 104, 26, 104, 20, 100, 16))
                    p.addPath(TalkSceneDrawing.arc(107, 36, 114, 28, 114, 14, 107, 6))
                }
                // On the sun disc in both schemes, so always the design's ink.
                ctx.stroke(arcs, with: .color(BirdRenderer.ink), style: .init(lineWidth: 3, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}
