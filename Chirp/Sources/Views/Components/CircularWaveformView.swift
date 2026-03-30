import SwiftUI

struct CircularWaveformView: View {
    var inputLevel: Float
    var pttState: PTTState
    var radius: CGFloat

    private let barCount = 24
    private let barWidth: CGFloat = 5.5
    private let maxBarLength: CGFloat = 28
    private let baseBarLength: CGFloat = 4

    private var activeColor: Color {
        switch pttState {
        case .idle: Constants.Colors.amber
        case .transmitting: Constants.Colors.hotRed
        case .receiving: Constants.Colors.electricGreen
        case .denied: Color.gray
        }
    }

    private var brightColor: Color {
        switch pttState {
        case .idle: Color(hex: 0xFFD966)
        case .transmitting: Color(hex: 0xFF6B6B)
        case .receiving: Color(hex: 0x6EE7A0)
        case .denied: Color(hex: 0x888888)
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let level = CGFloat(max(0.0, min(1.0, inputLevel)))

                // Degree markers at 0, 90, 180, 270
                let tickAngles: [Double] = [-.pi / 2.0, 0, .pi / 2.0, .pi]
                let tickInnerRadius = radius - 6
                let tickOuterRadius = radius - 1
                for tickAngle in tickAngles {
                    let tInnerX = center.x + cos(tickAngle) * tickInnerRadius
                    let tInnerY = center.y + sin(tickAngle) * tickInnerRadius
                    let tOuterX = center.x + cos(tickAngle) * tickOuterRadius
                    let tOuterY = center.y + sin(tickAngle) * tickOuterRadius
                    var tickPath = Path()
                    tickPath.move(to: CGPoint(x: tInnerX, y: tInnerY))
                    tickPath.addLine(to: CGPoint(x: tOuterX, y: tOuterY))
                    context.stroke(
                        tickPath,
                        with: .color(Constants.Colors.amber.opacity(0.5)),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                }

                for i in 0..<barCount {
                    let angle = (Double(i) / Double(barCount)) * .pi * 2.0 - .pi / 2.0
                    let barLength = computeBarLength(
                        index: i,
                        level: level,
                        time: time
                    )

                    let innerX = center.x + cos(angle) * (radius + 2)
                    let innerY = center.y + sin(angle) * (radius + 2)
                    let outerX = center.x + cos(angle) * (radius + 2 + barLength)
                    let outerY = center.y + sin(angle) * (radius + 2 + barLength)

                    let innerPoint = CGPoint(x: innerX, y: innerY)
                    let outerPoint = CGPoint(x: outerX, y: outerY)

                    // Glow behind bar
                    let glowOpacity = Double(level) * 0.35
                    if glowOpacity > 0.03 && pttState != .denied {
                        var glowPath = Path()
                        glowPath.move(to: innerPoint)
                        glowPath.addLine(to: outerPoint)
                        context.stroke(
                            glowPath,
                            with: .color(activeColor.opacity(glowOpacity * 0.5)),
                            style: StrokeStyle(lineWidth: barWidth + 9, lineCap: .round)
                        )
                        context.stroke(
                            glowPath,
                            with: .color(activeColor.opacity(glowOpacity * 0.25)),
                            style: StrokeStyle(lineWidth: barWidth + 18, lineCap: .round)
                        )
                    }

                    // Main bar with gradient (bright at tip, dim at base)
                    var barPath = Path()
                    barPath.move(to: innerPoint)
                    barPath.addLine(to: outerPoint)

                    let gradient = Gradient(colors: [
                        activeColor.opacity(0.4),
                        activeColor,
                        brightColor
                    ])
                    context.stroke(
                        barPath,
                        with: .linearGradient(
                            gradient,
                            startPoint: innerPoint,
                            endPoint: outerPoint
                        ),
                        style: StrokeStyle(lineWidth: barWidth, lineCap: .round)
                    )
                }
            }
        }
        .frame(width: (radius + maxBarLength + 16) * 2,
               height: (radius + maxBarLength + 16) * 2)
        .drawingGroup()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Audio waveform visualization")
        .accessibilityIdentifier(AccessibilityID.waveform)
    }

    // MARK: - Bar Length Computation

    private func computeBarLength(index: Int, level: CGFloat, time: Double) -> CGFloat {
        let phaseOffset = Double(index) * (2.0 * .pi / Double(barCount))

        switch pttState {
        case .transmitting:
            // Active dancing bars driven by audio level
            let wave1 = sin(time * 4.0 + phaseOffset) * 0.3
            let wave2 = sin(time * 6.5 + phaseOffset * 1.6) * 0.2
            let wave3 = sin(time * 2.8 + phaseOffset * 0.7) * 0.15
            let combined = 0.5 + wave1 + wave2 + wave3
            let length = baseBarLength + maxBarLength * level * CGFloat(combined) * 1.3
            return max(baseBarLength, min(maxBarLength, length))

        case .receiving:
            // Smoother wave pattern for incoming audio
            let wave1 = sin(time * 2.5 + phaseOffset) * 0.25
            let wave2 = sin(time * 3.8 + phaseOffset * 1.3) * 0.15
            let combined = 0.55 + wave1 + wave2
            let length = baseBarLength + maxBarLength * level * CGFloat(combined) * 1.1
            return max(baseBarLength, min(maxBarLength, length))

        case .idle:
            // Gentle breathing animation
            let wave = sin(time * 1.0 + phaseOffset) * 0.2
            let breathe = sin(time * 0.6) * 0.15
            let length = baseBarLength + maxBarLength * 0.08 * CGFloat(0.6 + wave + breathe)
            return max(baseBarLength * 0.6, min(maxBarLength * 0.2, length))

        case .denied:
            return baseBarLength * 0.5
        }
    }
}
