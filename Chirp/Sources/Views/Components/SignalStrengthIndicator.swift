import SwiftUI

struct SignalStrengthIndicator: View {
    var level: Int // 0-3

    private let barCount = 4
    private let barSpacing: CGFloat = 2
    private let barWidth: CGFloat = 4

    var body: some View {
        HStack(alignment: .bottom, spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                let barHeight: CGFloat = CGFloat(index + 1) * 4
                let isFilled = index < level

                RoundedRectangle(cornerRadius: 1)
                    .fill(isFilled ? Color(hex: 0x30D158) : Color.gray.opacity(0.3))
                    .frame(width: barWidth, height: barHeight)
            }
        }
        .frame(height: CGFloat(barCount) * 4)
    }
}
