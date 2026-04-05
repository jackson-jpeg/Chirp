import SwiftUI

/// Animated radar-style view that shows discovered mesh peers as pulsing dots.
struct MeshRadarView: View {
    let discoveredPeers: [String]

    @State private var ring1Scale: CGFloat = 0.3
    @State private var ring2Scale: CGFloat = 0.3
    @State private var ring3Scale: CGFloat = 0.3
    @State private var ring1Opacity: Double = 0.6
    @State private var ring2Opacity: Double = 0.6
    @State private var ring3Opacity: Double = 0.6
    @State private var sweepAngle: Double = 0
    @State private var peerAppeared: Set<Int> = []

    private let amber = Constants.Colors.amber

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 * 0.85

            ZStack {
                // Concentric rings pulsing outward
                radarRing(scale: ring1Scale, opacity: ring1Opacity, radius: radius)
                    .position(center)
                radarRing(scale: ring2Scale, opacity: ring2Opacity, radius: radius)
                    .position(center)
                radarRing(scale: ring3Scale, opacity: ring3Opacity, radius: radius)
                    .position(center)

                // Static guide rings
                ForEach(1...3, id: \.self) { i in
                    Circle()
                        .stroke(amber.opacity(0.08), lineWidth: 0.5)
                        .frame(
                            width: radius * 2 * CGFloat(i) / 3,
                            height: radius * 2 * CGFloat(i) / 3
                        )
                        .position(center)
                }

                // Sweep line
                let sweepEnd = CGPoint(
                    x: center.x + cos(sweepAngle * .pi / 180) * radius,
                    y: center.y + sin(sweepAngle * .pi / 180) * radius
                )
                Path { path in
                    path.move(to: center)
                    path.addLine(to: sweepEnd)
                }
                .stroke(
                    LinearGradient(
                        colors: [amber.opacity(0.4), amber.opacity(0.0)],
                        startPoint: .init(x: 0.5, y: 0.5),
                        endPoint: .init(x: 1, y: 0.5)
                    ),
                    lineWidth: 1.5
                )

                // Sweep glow cone
                Path { path in
                    path.move(to: center)
                    path.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .degrees(sweepAngle - 30),
                        endAngle: .degrees(sweepAngle),
                        clockwise: false
                    )
                    path.closeSubpath()
                }
                .fill(
                    AngularGradient(
                        colors: [amber.opacity(0.0), amber.opacity(0.08)],
                        center: .init(x: center.x / geo.size.width, y: center.y / geo.size.height),
                        startAngle: .degrees(sweepAngle - 30),
                        endAngle: .degrees(sweepAngle)
                    )
                )

                // Center dot (you)
                Circle()
                    .fill(amber)
                    .frame(width: 10, height: 10)
                    .shadow(color: amber.opacity(0.6), radius: 8)
                    .position(center)

                // Discovered peers
                ForEach(Array(discoveredPeers.enumerated()), id: \.offset) { index, peerName in
                    let peerPos = peerPosition(index: index, center: center, radius: radius)
                    let appeared = peerAppeared.contains(index)

                    Group {
                        // Ping ring animation
                        Circle()
                            .stroke(amber.opacity(appeared ? 0.0 : 0.4), lineWidth: 1.5)
                            .frame(width: appeared ? 40 : 8, height: appeared ? 40 : 8)
                            .position(peerPos)

                        // Peer dot
                        Circle()
                            .fill(amber)
                            .frame(width: 8, height: 8)
                            .shadow(color: amber.opacity(0.5), radius: 6)
                            .scaleEffect(appeared ? 1.0 : 0.0)
                            .position(peerPos)

                        // Peer label
                        Text(peerName)
                            .font(Constants.Typography.monoSmall)
                            .foregroundStyle(amber.opacity(0.8))
                            .offset(x: peerPos.x - center.x, y: peerPos.y - center.y + 14)
                            .opacity(appeared ? 1.0 : 0.0)
                            .position(center)
                    }
                }
            }
        }
        .onAppear {
            startAnimations()
        }
        .onChange(of: discoveredPeers.count) { _, _ in
            revealNewPeers()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Mesh radar showing \(discoveredPeers.count) nearby peers"))
    }

    // MARK: - Subviews

    private func radarRing(scale: CGFloat, opacity: Double, radius: CGFloat) -> some View {
        Circle()
            .stroke(amber.opacity(opacity), lineWidth: 1.0)
            .frame(width: radius * 2 * scale, height: radius * 2 * scale)
    }

    // MARK: - Positioning

    private func peerPosition(index: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        // Deterministic spread using golden angle
        let goldenAngle = 137.508
        let angle = Double(index) * goldenAngle
        let radians = angle * .pi / 180
        // Place at 40-75% of radius for visual clarity
        let dist = radius * (0.4 + CGFloat(index % 4) * 0.1)
        return CGPoint(
            x: center.x + cos(radians) * dist,
            y: center.y + sin(radians) * dist
        )
    }

    // MARK: - Animations

    private func startAnimations() {
        // Sweep rotation
        withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
            sweepAngle = 360
        }

        // Ring 1 pulse
        withAnimation(.easeOut(duration: 2.5).repeatForever(autoreverses: false)) {
            ring1Scale = 1.0
            ring1Opacity = 0.0
        }

        // Ring 2 pulse (offset)
        withAnimation(.easeOut(duration: 2.5).repeatForever(autoreverses: false).delay(0.8)) {
            ring2Scale = 1.0
            ring2Opacity = 0.0
        }

        // Ring 3 pulse (offset)
        withAnimation(.easeOut(duration: 2.5).repeatForever(autoreverses: false).delay(1.6)) {
            ring3Scale = 1.0
            ring3Opacity = 0.0
        }

        // Reveal initial peers
        revealNewPeers()
    }

    private func revealNewPeers() {
        for i in 0..<discoveredPeers.count where !peerAppeared.contains(i) {
            let delay = Double(i - peerAppeared.count) * 0.6 + 0.3
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(delay)) {
                peerAppeared.insert(i)
            }
        }
    }
}
