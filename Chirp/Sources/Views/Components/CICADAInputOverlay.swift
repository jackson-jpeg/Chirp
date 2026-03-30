import SwiftUI

struct CICADAInputOverlay: View {
    @Binding var hiddenText: String
    let coverTextLength: Int
    let capacity: Int
    var onSend: () -> Void
    var onDismiss: () -> Void

    private var bytesUsed: Int { Data(hiddenText.utf8).count }
    private var bytesRemaining: Int { max(0, capacity - bytesUsed) }
    private var isOverCapacity: Bool { bytesUsed > capacity }

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "eye.slash.fill")
                    .foregroundStyle(Constants.Colors.amber)
                Text("Hidden Message")
                    .font(Constants.Typography.cardTitle)
                    .foregroundStyle(Constants.Colors.textPrimary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Constants.Colors.textTertiary)
                }
                .accessibilityLabel("Close hidden message input")
            }

            // Text input
            TextField("Secret message...", text: $hiddenText, axis: .vertical)
                .font(.system(.body, weight: .regular))
                .foregroundStyle(.white)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel("Hidden message input")

            // Capacity + Send
            HStack {
                // Capacity indicator
                Text("\(bytesRemaining) bytes remaining")
                    .font(Constants.Typography.monoSmall)
                    .foregroundStyle(isOverCapacity ? Constants.Colors.hotRed : Constants.Colors.textTertiary)

                if capacity == 0 {
                    Text("(type a cover message first)")
                        .font(Constants.Typography.monoSmall)
                        .foregroundStyle(Constants.Colors.textTertiary)
                }

                Spacer()

                // Send button
                Button(action: onSend) {
                    HStack(spacing: 6) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 12, weight: .bold))
                        Text("Send Hidden")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Constants.Colors.amber)
                    .clipShape(Capsule())
                }
                .disabled(hiddenText.isEmpty || isOverCapacity || capacity == 0)
                .opacity(hiddenText.isEmpty || isOverCapacity || capacity == 0 ? 0.4 : 1.0)
                .accessibilityLabel("Send message with hidden content")
            }
        }
        .padding(Constants.Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                        .stroke(Constants.Colors.amber.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
