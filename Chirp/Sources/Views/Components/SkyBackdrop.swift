import SwiftUI

// MARK: - SkyBackdrop
// The full-screen page behind every top-level screen, from the app icon:
// by day a pale sky with a few soft clouds, by night a navy dusk with stars.
// Decoration only, kept faint so text on it reads at full contrast (the
// content sits on `Constants.Colors.backgroundPrimary`-equivalent tones).

struct SkyBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(hex: 0x070D1F), Color(hex: 0x0D1630), Color(hex: 0x0D1630)]
                    : [Color(hex: 0xCFEAFB), Color(hex: 0xEEF7FD), Color(hex: 0xEEF7FD)],
                startPoint: .top,
                endPoint: .bottom
            )

            Canvas { context, size in
                if colorScheme == .dark {
                    drawStars(in: &context, size: size)
                } else {
                    drawClouds(in: &context, size: size)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    // Positions are fractions of the screen, fixed so the sky never shuffles.

    private static let clouds: [(x: CGFloat, y: CGFloat, scale: CGFloat)] = [
        (0.08, 0.07, 0.55), (0.68, 0.04, 0.75), (0.40, 0.19, 0.40), (0.86, 0.24, 0.45),
    ]

    private static let stars: [(x: CGFloat, y: CGFloat, r: CGFloat, alpha: Double)] = [
        (0.12, 0.05, 1.6, 0.55), (0.31, 0.11, 1.0, 0.35), (0.52, 0.03, 1.3, 0.45),
        (0.74, 0.08, 1.8, 0.60), (0.90, 0.15, 1.0, 0.35), (0.06, 0.21, 1.1, 0.30),
        (0.44, 0.24, 0.9, 0.25), (0.63, 0.18, 1.2, 0.35), (0.84, 0.31, 1.0, 0.25),
        (0.22, 0.34, 0.9, 0.20),
    ]

    private func drawClouds(in context: inout GraphicsContext, size: CGSize) {
        for cloud in Self.clouds {
            // The icon's cloud: three puffs over a flat base, 270×170 at scale 1.
            let s = cloud.scale * size.width / 390 * 0.45
            let origin = CGPoint(x: cloud.x * size.width, y: cloud.y * size.height)
            var shape = Path()
            shape.addEllipse(in: CGRect(x: -60 * s, y: -60 * s, width: 120 * s, height: 120 * s))
            shape.addEllipse(in: CGRect(x: -10 * s, y: -116 * s, width: 164 * s, height: 164 * s))
            shape.addEllipse(in: CGRect(x: 90 * s, y: -60 * s, width: 120 * s, height: 120 * s))
            shape.addRect(CGRect(x: 0, y: 0, width: 150 * s, height: 60 * s))
            let placed = shape.offsetBy(dx: origin.x, dy: origin.y)
            context.fill(placed.offsetBy(dx: 0, dy: 10 * s), with: .color(Color(hex: 0xCFE8F7).opacity(0.55)))
            context.fill(placed, with: .color(.white.opacity(0.75)))
        }
    }

    private func drawStars(in context: inout GraphicsContext, size: CGSize) {
        for star in Self.stars {
            let rect = CGRect(
                x: star.x * size.width - star.r,
                y: star.y * size.height - star.r,
                width: star.r * 2,
                height: star.r * 2
            )
            context.fill(Circle().path(in: rect), with: .color(Color(hex: 0xF6E7C1).opacity(star.alpha)))
        }
    }
}
