import SwiftUI

/// Frosted glass container with configurable tint — the visual foundation of ChirpChirp's UI.
struct GlassContainer: ViewModifier {
    let tintColor: Color
    let cornerRadius: CGFloat
    let borderWidth: CGFloat
    let glowRadius: CGFloat
    let glowOpacity: Double

    init(
        tint: Color = Constants.Colors.amber,
        cornerRadius: CGFloat = Constants.Layout.glassCornerRadius,
        borderWidth: CGFloat = Constants.Layout.glassBorderWidth,
        glowRadius: CGFloat = 12,
        glowOpacity: Double = 0.2
    ) {
        self.tintColor = tint
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.glowRadius = glowRadius
        self.glowOpacity = glowOpacity
    }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.55),
                                Color.black.opacity(0.25)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tintColor.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        tintColor.opacity(0.5),
                                        tintColor.opacity(0.15),
                                        tintColor.opacity(0.35)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: borderWidth
                            )
                    )
            )
            .shadow(color: tintColor.opacity(glowOpacity), radius: glowRadius, x: 0, y: 4)
    }
}

extension View {
    /// Apply frosted glass treatment with the given tint color.
    func glassContainer(
        tint: Color = Constants.Colors.amber,
        cornerRadius: CGFloat = Constants.Layout.glassCornerRadius,
        glow: CGFloat = 12,
        glowOpacity: Double = 0.2
    ) -> some View {
        modifier(GlassContainer(tint: tint, cornerRadius: cornerRadius, glowRadius: glow, glowOpacity: glowOpacity))
    }
}
