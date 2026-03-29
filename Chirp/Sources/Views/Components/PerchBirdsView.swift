import SwiftUI

// MARK: - PerchBirdsView
// Two round amber birds perched on a wire — one chirping, one listening.
// The brand mascot for ChirpChirp, drawn entirely with SwiftUI shapes.

struct PerchBirdsView: View {
    var size: CGFloat = 200
    var isAnimating: Bool = true

    // Animation state
    @State private var breathOffset: CGFloat = 0
    @State private var soundLineOpacities: [Double] = [0.0, 0.0, 0.0]
    @State private var listenerTilt: Double = 0
    @State private var wireSway: CGFloat = 0
    @State private var chirpBurst: Bool = false
    @State private var chirpHeadTilt: Double = 0

    // Colors
    private let amber = Color(hex: 0xFFB800)
    private let darkAmber = Color(hex: 0xE6A600)
    private let beakOrange = Color(hex: 0xFF6B35)
    private let eyeColor = Color(hex: 0x0F172A)

    private var scale: CGFloat { size / 200.0 }

    var body: some View {
        Canvas { context, canvasSize in
            let cx = canvasSize.width / 2
            let cy = canvasSize.height / 2
            let s = scale

            // -- Wire --
            let wireY = cy + 28 * s + wireSway
            var wirePath = Path()
            // Slight catenary curve
            wirePath.move(to: CGPoint(x: 0, y: wireY - 2 * s))
            wirePath.addQuadCurve(
                to: CGPoint(x: canvasSize.width, y: wireY - 2 * s),
                control: CGPoint(x: cx, y: wireY + 6 * s)
            )
            context.stroke(
                wirePath,
                with: .color(amber.opacity(0.5)),
                lineWidth: max(1.5 * s, 1)
            )

            // -- Left Bird (Chirper) --
            let leftX = cx - 28 * s
            let leftY = cy + 8 * s + breathOffset

            drawBird(
                context: &context, x: leftX, y: leftY, s: s,
                facingRight: true, beakOpen: true,
                headTiltDeg: chirpHeadTilt
            )

            // Sound lines from beak
            let soundBaseX = leftX + 22 * s
            let soundBaseY = leftY - 8 * s
            for i in 0..<3 {
                let offset = CGFloat(i + 1) * 7 * s
                let arcSize = CGFloat(6 + i * 4) * s
                var arcPath = Path()
                arcPath.addArc(
                    center: CGPoint(x: soundBaseX + offset, y: soundBaseY),
                    radius: arcSize,
                    startAngle: .degrees(-40),
                    endAngle: .degrees(40),
                    clockwise: false
                )
                let lineOpacity = soundLineOpacities[safe: i] ?? 0.0
                let brightness = chirpBurst ? min(lineOpacity + 0.3, 1.0) : lineOpacity
                context.stroke(
                    arcPath,
                    with: .color(amber.opacity(brightness)),
                    lineWidth: max(2.0 * s - CGFloat(i) * 0.3 * s, 0.8)
                )
            }

            // -- Right Bird (Listener) --
            let rightX = cx + 28 * s
            let rightY = cy + 8 * s + breathOffset * 0.6  // Slightly less bob

            // Apply listener tilt by adjusting position slightly
            let tiltOffsetX = -sin(listenerTilt * .pi / 180) * 3 * s
            let tiltOffsetY = -abs(sin(listenerTilt * .pi / 180)) * 2 * s

            drawBird(
                context: &context,
                x: rightX + tiltOffsetX, y: rightY + tiltOffsetY, s: s,
                facingRight: false, beakOpen: false,
                headTiltDeg: listenerTilt
            )

            // Feet on wire for both birds
            drawFeet(context: &context, x: leftX, wireY: wireY, s: s, facingRight: true)
            drawFeet(context: &context, x: rightX + tiltOffsetX, wireY: wireY, s: s, facingRight: false)

        }
        .frame(width: size, height: size * 0.6)
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

    // MARK: - Draw Bird

    private func drawBird(
        context: inout GraphicsContext, x: CGFloat, y: CGFloat, s: CGFloat,
        facingRight: Bool, beakOpen: Bool, headTiltDeg: Double
    ) {
        let dir: CGFloat = facingRight ? 1 : -1

        // Body — round circle
        let bodyRadius: CGFloat = 18 * s
        let bodyRect = CGRect(
            x: x - bodyRadius, y: y - bodyRadius,
            width: bodyRadius * 2, height: bodyRadius * 2
        )
        context.fill(
            Circle().path(in: bodyRect),
            with: .linearGradient(
                Gradient(colors: [amber, darkAmber]),
                startPoint: CGPoint(x: x, y: y - bodyRadius),
                endPoint: CGPoint(x: x, y: y + bodyRadius)
            )
        )

        // Wing — darker ellipse on back side
        let wingX = x - dir * 5 * s
        let wingY = y + 2 * s
        let wingW: CGFloat = 14 * s
        let wingH: CGFloat = 10 * s
        let wingRect = CGRect(
            x: wingX - wingW / 2, y: wingY - wingH / 2,
            width: wingW, height: wingH
        )
        context.fill(
            Ellipse().path(in: wingRect),
            with: .color(darkAmber.opacity(0.7))
        )

        // Eye
        let eyeX = x + dir * 7 * s
        let eyeY = y - 5 * s
        let eyeRadius: CGFloat = 3.2 * s
        let eyeRect = CGRect(
            x: eyeX - eyeRadius, y: eyeY - eyeRadius,
            width: eyeRadius * 2, height: eyeRadius * 2
        )
        context.fill(Circle().path(in: eyeRect), with: .color(eyeColor))

        // Eye highlight
        let hlRadius: CGFloat = 1.2 * s
        let hlRect = CGRect(
            x: eyeX + dir * 1 * s - hlRadius,
            y: eyeY - 1.5 * s - hlRadius,
            width: hlRadius * 2, height: hlRadius * 2
        )
        context.fill(Circle().path(in: hlRect), with: .color(.white.opacity(0.9)))

        // Beak
        let beakX = x + dir * 16 * s
        let beakY = y - 2 * s
        if beakOpen {
            // Upper beak
            var upperBeak = Path()
            upperBeak.move(to: CGPoint(x: x + dir * 14 * s, y: beakY - 2 * s))
            upperBeak.addLine(to: CGPoint(x: beakX + dir * 5 * s, y: beakY - 4 * s))
            upperBeak.addLine(to: CGPoint(x: x + dir * 14 * s, y: beakY))
            upperBeak.closeSubpath()
            context.fill(upperBeak, with: .color(beakOrange))

            // Lower beak
            var lowerBeak = Path()
            lowerBeak.move(to: CGPoint(x: x + dir * 14 * s, y: beakY))
            lowerBeak.addLine(to: CGPoint(x: beakX + dir * 4 * s, y: beakY + 3 * s))
            lowerBeak.addLine(to: CGPoint(x: x + dir * 14 * s, y: beakY + 2 * s))
            lowerBeak.closeSubpath()
            context.fill(lowerBeak, with: .color(beakOrange.opacity(0.85)))
        } else {
            // Closed beak
            var beak = Path()
            beak.move(to: CGPoint(x: x + dir * 14 * s, y: beakY - 1 * s))
            beak.addLine(to: CGPoint(x: beakX + dir * 4 * s, y: beakY))
            beak.addLine(to: CGPoint(x: x + dir * 14 * s, y: beakY + 1 * s))
            beak.closeSubpath()
            context.fill(beak, with: .color(beakOrange))
        }

        // Tail feathers on back
        let tailX = x - dir * 16 * s
        let tailY = y + 4 * s
        for i in 0..<3 {
            var feather = Path()
            let spread = CGFloat(i - 1) * 4 * s
            feather.move(to: CGPoint(x: x - dir * 14 * s, y: tailY))
            feather.addLine(to: CGPoint(x: tailX - dir * 6 * s, y: tailY - 6 * s + spread))
            feather.addLine(to: CGPoint(x: tailX - dir * 3 * s, y: tailY - 4 * s + spread))
            feather.closeSubpath()
            context.fill(feather, with: .color(darkAmber.opacity(0.5 + Double(i) * 0.1)))
        }
    }

    // MARK: - Draw Feet

    private func drawFeet(
        context: inout GraphicsContext, x: CGFloat, wireY: CGFloat, s: CGFloat, facingRight: Bool
    ) {
        let dir: CGFloat = facingRight ? 1 : -1
        let footColor = beakOrange

        for side in [-1.0, 1.0] {
            let footX = x + CGFloat(side) * 4 * s
            // Leg
            var leg = Path()
            leg.move(to: CGPoint(x: footX, y: wireY - 16 * s))
            leg.addLine(to: CGPoint(x: footX, y: wireY))
            context.stroke(leg, with: .color(footColor), lineWidth: max(1.5 * s, 1))

            // Toes gripping wire
            for toe in [-1.0, 0.0, 1.0] {
                var toePath = Path()
                toePath.move(to: CGPoint(x: footX, y: wireY))
                toePath.addLine(to: CGPoint(
                    x: footX + toe * 2.5 * s * dir,
                    y: wireY + 2 * s
                ))
                context.stroke(toePath, with: .color(footColor), lineWidth: max(1.2 * s, 0.8))
            }
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
