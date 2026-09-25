import SwiftUI

// MARK: - PerchBirdsView
// Two round sunny birds perched on a wire — one chirping, one listening — with
// the chirp travelling down the wire between them. The brand mascot, drawn
// from the app icon's geometry (icon.svg) so the two always match.

struct PerchBirdsView: View {
    var size: CGFloat = 200
    var isAnimating: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    // Animation state
    @State private var breathOffset: CGFloat = 0
    @State private var soundLineOpacities: [Double] = [0.0, 0.0, 0.0]
    @State private var listenerTilt: Double = 0
    @State private var wireSway: CGFloat = 0
    @State private var chirpBurst: Bool = false
    @State private var chirpHeadTilt: Double = 0

    // Colors — the icon's, in both modes
    private let bodyColor = Constants.Colors.sun
    private let feather = Constants.Colors.wing
    private let beak = Constants.Colors.beak
    private let eyeColor = Constants.Colors.navy

    /// The wire is navy against the day sky and pale cloud against the night.
    private var wireColor: Color {
        colorScheme == .dark ? Constants.Colors.cloud : Constants.Colors.navy
    }

    private var scale: CGFloat { size / 200.0 }

    /// icon.svg draws a bird with a 150-unit body radius; ours is 18 points
    /// at `size` 200.
    private static let iconUnit: CGFloat = 18.0 / 150.0

    var body: some View {
        Canvas { context, canvasSize in
            let cx = canvasSize.width / 2
            let cy = canvasSize.height / 2
            let s = scale
            let k = Self.iconUnit * s

            // -- Wire, with the chirp as a waveform between the birds --
            let wireY = cy + 28 * s + wireSway
            let pulse = chirpBurst ? 1.0 : 0.45 + 0.55 * (soundLineOpacities[safe: 1] ?? 0)
            context.stroke(
                wirePath(width: canvasSize.width, cx: cx, wireY: wireY, s: s, amplitude: CGFloat(pulse)),
                with: .color(wireColor),
                style: StrokeStyle(lineWidth: max(1.4 * s, 1), lineCap: .round, lineJoin: .round)
            )

            // Legs end on the wire: 178 icon units below the body centre.
            let perchY = wireY - 178 * k

            // -- Left Bird (Chirper) --
            drawBird(
                context: &context, x: cx - 26 * s, y: perchY + breathOffset * 0.3, k: k,
                facingRight: true, beakOpen: true,
                tiltDeg: chirpHeadTilt
            )

            // -- Right Bird (Listener) --
            drawBird(
                context: &context, x: cx + 26 * s, y: perchY + breathOffset * 0.2, k: k,
                facingRight: false, beakOpen: false,
                tiltDeg: listenerTilt
            )
        }
        .frame(width: size, height: size * 0.6)
        .accessibilityHidden(true)
        .onAppear {
            guard isAnimating else { return }
            startAnimations()
        }
        .onChange(of: isAnimating) { _, newValue in
            if newValue {
                startAnimations()
            }
        }
    }

    // MARK: - Wire

    /// A straight wire with the icon's zigzag chirp in the middle. The
    /// zigzag's height follows `amplitude` (0...1) so it pulses as they talk.
    private func wirePath(width: CGFloat, cx: CGFloat, wireY: CGFloat, s: CGFloat, amplitude: CGFloat) -> Path {
        // icon.svg's zigzag, relative to its centre, in icon pixels.
        let zigzag: [(CGFloat, CGFloat)] = [
            (-76, 0), (-60, -20), (-44, 26), (-28, -46), (-12, 50), (0, -66),
            (12, 50), (28, -46), (44, 26), (60, -20), (76, 0),
        ]
        let unit = 18.0 / 135.0 * s   // the icon's birds are drawn at 0.9 scale
        var path = Path()
        path.move(to: CGPoint(x: 0, y: wireY))
        for (dx, dy) in zigzag {
            path.addLine(to: CGPoint(x: cx + dx * unit, y: wireY + dy * unit * amplitude))
        }
        path.addLine(to: CGPoint(x: width, y: wireY))
        return path
    }

    // MARK: - Draw Bird

    /// Draws icon.svg's bird with its body centred at (x, y). Paths are in the
    /// icon's own units (facing right), mapped by `k` points per unit,
    /// mirrored for the listener and tilted about the body centre.
    private func drawBird(
        context: inout GraphicsContext, x: CGFloat, y: CGFloat, k: CGFloat,
        facingRight: Bool, beakOpen: Bool, tiltDeg: Double
    ) {
        let dir: CGFloat = facingRight ? 1 : -1
        let transform = CGAffineTransform(scaleX: dir * k, y: k)
            .concatenating(CGAffineTransform(rotationAngle: CGFloat(tiltDeg * .pi / 180) * dir * 0.5))
            .concatenating(CGAffineTransform(translationX: x, y: y))

        func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
            var path = Path()
            path.addLines(points.map { CGPoint(x: $0.0, y: $0.1) })
            path.closeSubpath()
            return path.applying(transform)
        }

        func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)).applying(transform)
        }

        // Tail
        context.fill(polygon([(-128, 30), (-196, 4), (-176, 38), (-204, 62), (-140, 70)]), with: .color(feather))

        // Legs
        var legs = Path()
        legs.move(to: CGPoint(x: -22, y: 140))
        legs.addLine(to: CGPoint(x: -26, y: 178))
        legs.move(to: CGPoint(x: 26, y: 140))
        legs.addLine(to: CGPoint(x: 30, y: 178))
        context.stroke(
            legs.applying(transform),
            with: .color(feather),
            style: StrokeStyle(lineWidth: max(10 * k, 1), lineCap: .round)
        )

        // Crest
        var crest = Path()
        crest.move(to: CGPoint(x: -10, y: -146))
        crest.addCurve(to: CGPoint(x: 28, y: -176), control1: CGPoint(x: -4, y: -180), control2: CGPoint(x: 16, y: -188))
        crest.addCurve(to: CGPoint(x: 12, y: -144), control1: CGPoint(x: 14, y: -170), control2: CGPoint(x: 10, y: -158))
        crest.closeSubpath()
        context.fill(crest.applying(transform), with: .color(feather))

        // Body
        context.fill(circle(0, 0, 150), with: .color(bodyColor))

        // Wing
        var wing = Path()
        wing.move(to: CGPoint(x: -122, y: -6))
        wing.addCurve(to: CGPoint(x: 30, y: 30), control1: CGPoint(x: -70, y: -44), control2: CGPoint(x: 6, y: -26))
        wing.addCurve(to: CGPoint(x: -124, y: 70), control1: CGPoint(x: 8, y: 86), control2: CGPoint(x: -66, y: 104))
        wing.addCurve(to: CGPoint(x: -122, y: -6), control1: CGPoint(x: -150, y: 48), control2: CGPoint(x: -148, y: 12))
        wing.closeSubpath()
        context.fill(wing.applying(transform), with: .color(feather))

        // Eye
        context.fill(circle(64, -46, 23), with: .color(eyeColor))
        context.fill(circle(72, -54, 7), with: .color(.white))

        // Beak
        if beakOpen {
            context.fill(polygon([(134, -48), (190, -38), (136, -24)]), with: .color(beak))
            context.fill(polygon([(136, -16), (180, -4), (132, 0)]), with: .color(beak))
        } else {
            context.fill(polygon([(134, -44), (186, -26), (134, -8)]), with: .color(beak))
        }
    }

    // MARK: - Animations

    private func startAnimations() {
        // Breathing bob
        withAnimation(
            .easeInOut(duration: 0.8)
            .repeatForever(autoreverses: true)
        ) {
            breathOffset = -3
        }

        // Wire sway
        withAnimation(
            .easeInOut(duration: 2.5)
            .repeatForever(autoreverses: true)
        ) {
            wireSway = 1.5
        }

        // Sound lines pulsing in sequence
        startSoundLinePulse()

        // Listener tilt
        withAnimation(
            .easeInOut(duration: 1.5)
            .repeatForever(autoreverses: true)
        ) {
            listenerTilt = 8
        }

        // Periodic chirp burst every 3-4 seconds
        startChirpBurst()
    }

    private func startSoundLinePulse() {
        // Staggered fade in/out for each sound line
        func pulseLoop() {
            guard isAnimating else { return }
            for i in 0..<3 {
                // Fade in
                withAnimation(.easeIn(duration: 0.25).delay(Double(i) * 0.15)) {
                    soundLineOpacities[i] = 0.7
                }
                // Fade out
                withAnimation(.easeOut(duration: 0.4).delay(Double(i) * 0.15 + 0.4)) {
                    soundLineOpacities[i] = 0.15
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                pulseLoop()
            }
        }
        pulseLoop()
    }

    private func startChirpBurst() {
        func burstLoop() {
            guard isAnimating else { return }
            let delay = Double.random(in: 3.0...4.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard isAnimating else { return }
                // Head tilt up
                withAnimation(.easeOut(duration: 0.12)) {
                    chirpHeadTilt = -8
                    chirpBurst = true
                }
                // Return
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.2)) {
                    chirpHeadTilt = 0
                }
                withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                    chirpBurst = false
                }
                burstLoop()
            }
        }
        burstLoop()
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
