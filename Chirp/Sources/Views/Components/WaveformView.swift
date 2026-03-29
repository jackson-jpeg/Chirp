import SwiftUI

struct WaveformView: View {
    var inputLevel: Float
    var pttState: PTTState

    private let barCount = 9
    private let maxBarHeight: CGFloat = 55
    private let barWidth: CGFloat = 5
    private let barSpacing: CGFloat = 4

    private var activeColor: Color {
        switch pttState {
        case .idle:
            return Constants.Colors.amber
        case .transmitting:
            return Constants.Colors.hotRed
        case .receiving:
            return Constants.Colors.electricGreen
        case .denied:
            return Constants.Colors.hotRed
        }
    }

    private var brightColor: Color {
        switch pttState {
        case .idle:
            return Color(hex: 0xFFD966)
        case .transmitting:
            return Color(hex: 0xFF6B6B)
        case .receiving:
            return Color(hex: 0x6EE7A0)
        case .denied:
            return Color(hex: 0xFF6B6B)
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
                let startX = (size.width - totalWidth) / 2.0
                let centerY = size.height / 2.0
                let level = CGFloat(max(0.05, min(1.0, inputLevel)))

                for i in 0..<barCount {
                    let height = computeBarHeight(
                        index: i,
                        level: level,
                        time: time
                    )
                    let halfH = height / 2.0
                    let x = startX + CGFloat(i) * (barWidth + barSpacing)

                    // Glow behind bar
                    let glowRect = CGRect(
                        x: x - 3,
                        y: centerY - halfH - 3,
                        width: barWidth + 6,
                        height: height + 6
                    )
                    let glowOpacity = Double(level) * 0.4
                    if glowOpacity > 0.05 {
                        let glowPath = RoundedRectangle(cornerRadius: barWidth / 2 + 3)
                            .path(in: glowRect)
                        context.fill(
                            glowPath,
                            with: .color(activeColor.opacity(glowOpacity))
                        )
                        // Apply blur via layering multiple slightly offset fills
                        let glowRect2 = glowRect.insetBy(dx: -2, dy: -2)
                        let glowPath2 = RoundedRectangle(cornerRadius: barWidth / 2 + 5)
                            .path(in: glowRect2)
                        context.fill(
                            glowPath2,
                            with: .color(activeColor.opacity(glowOpacity * 0.3))
                        )
                    }

                    // Main bar with gradient
                    let barRect = CGRect(
                        x: x,
                        y: centerY - halfH,
                        width: barWidth,
                        height: height
                    )
                    let barPath = RoundedRectangle(cornerRadius: barWidth / 2)
                        .path(in: barRect)

                    let gradient = Gradient(colors: [
                        brightColor,
                        activeColor,
                        activeColor.opacity(0.5)
                    ])
                    context.fill(
                        barPath,
                        with: .linearGradient(
                            gradient,
                            startPoint: CGPoint(x: x + barWidth / 2, y: centerY - halfH),
                            endPoint: CGPoint(x: x + barWidth / 2, y: centerY + halfH)
                        )
                    )
                }
            }
        }
        .frame(height: maxBarHeight * 2 + 10)
        .drawingGroup()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Audio level waveform")
    }

    private func computeBarHeight(index: Int, level: CGFloat, time: Double) -> CGFloat {
        let center = CGFloat(barCount - 1) / 2.0
        let distanceFromCenter = abs(CGFloat(index) - center) / center
        let baseEnvelope = 1.0 - (distanceFromCenter * 0.45)

        // Per-bar phase offset for organic feel
        let phaseOffset = Double(index) * 0.7

        // Different response speeds per bar
        let speed: Double
        switch pttState {
        case .transmitting:
            // Active dancing — multiple sin waves combined
            let speedBase = 3.5 + Double(index % 3) * 1.2
            speed = speedBase
            let wave1 = sin(time * speed + phaseOffset) * 0.35
            let wave2 = sin(time * speed * 1.7 + phaseOffset * 1.3) * 0.2
            let wave3 = sin(time * speed * 0.6 + phaseOffset * 0.5) * 0.15
            let combined = 0.5 + wave1 + wave2 + wave3
            let height = maxBarHeight * level * baseEnvelope * CGFloat(combined) * 1.6
            return max(4, min(maxBarHeight, height))

        case .receiving:
            // Smoother incoming signal pattern
            speed = 2.0 + Double(index % 2) * 0.5
            let wave1 = sin(time * speed + phaseOffset) * 0.3
            let wave2 = sin(time * speed * 0.8 + phaseOffset * 1.5) * 0.15
            let combined = 0.55 + wave1 + wave2
            let height = maxBarHeight * level * baseEnvelope * CGFloat(combined) * 1.4
            return max(4, min(maxBarHeight, height))

        case .idle:
            // Gentle idle breathing
            speed = 1.2 + Double(index) * 0.15
            let wave = sin(time * speed + phaseOffset) * 0.15
            let height = maxBarHeight * 0.12 * baseEnvelope * CGFloat(0.6 + wave)
            return max(4, min(maxBarHeight * 0.25, height))

        case .denied:
            return 4
        }
    }
}
