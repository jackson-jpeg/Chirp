import SwiftUI
import ChirpCore

/// One person's feather colors. The seven palettes are the approved Dawn
/// Chorus set, in the order of `MakeBird.dc.html`'s Feathers row, and index
/// for index the same as `ChirpCore.Bird.palette`.
struct BirdPalette: Equatable, Sendable {
    let name: String
    let body: Color
    let belly: Color
    let cap: Color
    let wing: Color
    let tail: Color
    /// Only the yellow bird has the gold tuft (the icon's talker).
    let tuft: Color?
    /// The swatch shown in the Feathers row.
    var swatch: Color { body }

    static let all: [BirdPalette] = [
        // Blue, Yellow, Coral, Green and Lilac are exact from the design files.
        // Teal and Orange appear only as swatches there (#2CB7B0, #FFA94D);
        // their belly, cap, wing and tail are shaded the same way as the others.
        .init(name: "Blue", body: .hex(0x4FA8E8), belly: .hex(0xCDE9FA), cap: .hex(0x2F8ED6), wing: .hex(0x2F8ED6), tail: .hex(0x2A7FC2), tuft: nil),
        .init(name: "Teal", body: .hex(0x2CB7B0), belly: .hex(0xC9EFEC), cap: .hex(0x1E968F), wing: .hex(0x22A39C), tail: .hex(0x1B8A84), tuft: nil),
        .init(name: "Yellow", body: .hex(0xFFC531), belly: .hex(0xFFE596), cap: .hex(0xFFB81C), wing: .hex(0xF2A100), tail: .hex(0xD98A00), tuft: .hex(0xF2A100)),
        .init(name: "Coral", body: .hex(0xFF8C69), belly: .hex(0xFFD6C4), cap: .hex(0xE2603F), wing: .hex(0xE86A4A), tail: .hex(0xC9533A), tuft: nil),
        .init(name: "Green", body: .hex(0x6CC49A), belly: .hex(0xD3F2E1), cap: .hex(0x2E8B62), wing: .hex(0x4FAE82), tail: .hex(0x3E9670), tuft: nil),
        .init(name: "Lilac", body: .hex(0xB39DF2), belly: .hex(0xECE5FF), cap: .hex(0x7D63D6), wing: .hex(0x9C84EA), tail: .hex(0x8A70DE), tuft: nil),
        .init(name: "Orange", body: .hex(0xFFA94D), belly: .hex(0xFFE3C4), cap: .hex(0xE8862A), wing: .hex(0xF0922F), tail: .hex(0xD27420), tuft: nil),
    ]

    static subscript(_ bird: ChirpCore.Bird) -> BirdPalette { all[Int(bird.palette) % all.count] }
    /// Its place in `all`, which is `ChirpCore.Bird.palette`.
    var index: Int { Self.all.firstIndex(of: self) ?? 0 }
    static let blue = all[0], teal = all[1], yellow = all[2], coral = all[3], green = all[4], lilac = all[5], orange = all[6]
}

/// Draws the approved bird into a Canvas. `center` is where the design puts
/// the symbol's origin (its `translate`), `scale` its `scale`, and
/// `facingLeft` its negative x scale.
enum BirdRenderer {
    static let ink = Color.hex(0x14233F)
    static let legs = Color.hex(0xE07A2E)
    static let cheek = Color.hex(0xFF8A7A)

    static func draw(_ ctx: inout GraphicsContext, palette: BirdPalette, beakOpen: Bool,
                     center: CGPoint, scale: CGFloat, facingLeft: Bool = false) {
        var c = ctx
        c.translateBy(x: center.x, y: center.y)
        c.scaleBy(x: facingLeft ? -scale : scale, y: scale)
        c.fill(BirdPaths.tail, with: .color(palette.tail))
        c.fill(BirdPaths.body, with: .color(palette.body))
        if let tuft = palette.tuft { c.fill(BirdPaths.tuft, with: .color(tuft)) }
        c.fill(BirdPaths.belly, with: .color(palette.belly))
        c.fill(BirdPaths.cap, with: .color(palette.cap))
        c.fill(BirdPaths.wing, with: .color(palette.wing))
        c.stroke(BirdPaths.wingLines, with: .color(ink.opacity(0.28)), style: .init(lineWidth: 3.5, lineCap: .round))
        c.fill(Path(ellipseIn: CGRect(x: 62, y: -36, width: 28, height: 20)), with: .color(cheek.opacity(0.55)))
        c.fill(Path(ellipseIn: CGRect(x: 62, y: -68, width: 24, height: 24)), with: .color(ink))
        c.fill(Path(ellipseIn: CGRect(x: 73.8, y: -64.2, width: 8.4, height: 8.4)), with: .color(.white))
        c.stroke(BirdPaths.legs, with: .color(legs), style: .init(lineWidth: 7, lineCap: .round))
        c.stroke(BirdPaths.feet, with: .color(legs), style: .init(lineWidth: 6, lineCap: .round))
        c.translateBy(x: 112, y: -52)
        if beakOpen {
            c.fill(BirdPaths.beakOpenUpper, with: .color(.hex(0xFF7A45)))
            c.fill(BirdPaths.beakOpenLower, with: .color(.hex(0xE9632F)))
            c.fill(BirdPaths.beakOpenMouth, with: .color(.hex(0xB23A2A)))
        } else {
            c.fill(BirdPaths.beakClosedUpper, with: .color(.hex(0xFF7A45)))
            c.stroke(BirdPaths.beakClosedLine, with: .color(.hex(0xC4502A)), lineWidth: 2.5)
        }
    }

    /// The two sound arcs drawn in front of a talking bird (`)))` in the files),
    /// in the scene's own coordinates.
    static func drawChirpArcs(_ ctx: inout GraphicsContext, small: (CGPoint, CGPoint, CGPoint),
                              large: (CGPoint, CGPoint, CGPoint, CGPoint), width: CGFloat, color: Color = ink) {
        var p = Path()
        p.move(to: small.0); p.addCurve(to: small.2, control1: small.1, control2: small.1)
        p.move(to: large.0); p.addCurve(to: large.3, control1: large.1, control2: large.2)
        ctx.stroke(p, with: .color(color), style: .init(lineWidth: width, lineCap: .round))
    }

    /// The bird's drawn extent in its own coordinates (tail tip to open beak,
    /// tuft to feet), used to fit a lone bird into a frame.
    static let bounds = CGRect(x: -174, y: -142, width: 334, height: 272)
}

/// A lone bird, fitted to its frame: avatars, rows, the talk button.
/// Beak open while that person is talking.
struct BirdView: View {
    var palette: BirdPalette
    var talking: Bool = false
    var facingLeft: Bool = false

    var body: some View {
        Canvas { ctx, size in
            let b = BirdRenderer.bounds
            let s = min(size.width / b.width, size.height / b.height)
            let cx = size.width / 2 - (b.midX * s) * (facingLeft ? -1 : 1)
            let cy = size.height / 2 - b.midY * s
            BirdRenderer.draw(&ctx, palette: palette, beakOpen: talking,
                              center: CGPoint(x: cx, y: cy), scale: s, facingLeft: facingLeft)
        }
        .aspectRatio(BirdRenderer.bounds.width / BirdRenderer.bounds.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

extension Color {
    static func hex(_ v: UInt32, opacity: Double = 1) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255, opacity: opacity)
    }
}
