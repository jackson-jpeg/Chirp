import SwiftUI

struct WaveformView: View {
    var inputLevel: Float
    var pttState: PTTState

    @State private var animationOffsets: [CGFloat] = Array(repeating: 0, count: 7)

    private let barCount = 7
    private let maxBarHeight: CGFloat = 50
    private let barWidth: CGFloat = 6
    private let barSpacing: CGFloat = 5

    private var activeColor: Color {
        switch pttState {
        case .idle:
            return Color(hex: 0xFFB800)
        case .transmitting:
            return Color(hex: 0xFF3B30)
        case .receiving:
            return Color(hex: 0x30D158)
        case .denied:
            return Color(hex: 0xFF3B30)
        }
    }

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(activeColor.opacity(0.8))
                    .frame(width: barWidth, height: barHeight(for: index))
                    .shadow(color: activeColor.opacity(0.3), radius: 4)
            }
        }
        .frame(height: maxBarHeight)
        .onAppear {
            startAnimating()
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let level = CGFloat(max(0.05, min(1.0, inputLevel)))

        // Create a wave pattern: center bars taller, edges shorter
        let center = CGFloat(barCount - 1) / 2.0
        let distanceFromCenter = abs(CGFloat(index) - center) / center
        let baseMultiplier = 1.0 - (distanceFromCenter * 0.5)

        let randomOffset = animationOffsets[index]
        let height = maxBarHeight * level * baseMultiplier + randomOffset

        return max(4, min(maxBarHeight, height))
    }

    private func startAnimating() {
        Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.08)) {
                    for i in 0..<barCount {
                        let jitter = CGFloat.random(in: -6...6) * CGFloat(max(0.1, inputLevel))
                        animationOffsets[i] = jitter
                    }
                }
            }
        }
    }
}
