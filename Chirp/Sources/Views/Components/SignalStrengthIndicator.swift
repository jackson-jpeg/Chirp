import SwiftUI

struct SignalStrengthIndicator: View {
    var level: Int // 0-4

    @State private var animatedLevel: Int = 0

    private let barCount = 4
    private let barSpacing: CGFloat = 1.5
    private let barWidth: CGFloat = 3.5
    private let maxBarHeight: CGFloat = 14

    private let activeColor = Constants.Colors.amber
    private let inactiveColor = Color.white.opacity(0.15)

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .bottom, spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    let fraction = CGFloat(index + 1) / CGFloat(barCount)
                    let barHeight = maxBarHeight * fraction
                    let isFilled = index < animatedLevel

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isFilled ? activeColor : inactiveColor)
                        .frame(width: barWidth, height: barHeight)
                        .animation(.spring(response: 0.35, dampingFraction: 0.7).delay(Double(index) * 0.05), value: animatedLevel)
                }
            }
            .frame(height: maxBarHeight, alignment: .bottom)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Signal strength \(level) of \(barCount)")
        .onAppear {
            animatedLevel = level.clamped(to: 0...barCount)
        }
        .onChange(of: level) { _, newLevel in
            withAnimation {
                animatedLevel = newLevel.clamped(to: 0...barCount)
            }
        }
    }
}

// MARK: - Clamped helper

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
