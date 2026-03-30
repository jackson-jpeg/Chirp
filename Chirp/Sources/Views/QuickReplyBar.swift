import SwiftUI

struct QuickReplyBar: View {
    let replies: [QuickReply]
    let onTap: (QuickReply) -> Void

    @State private var previewReply: QuickReply?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(replies) { reply in
                    quickReplyChip(reply)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Chip

    private func quickReplyChip(_ reply: QuickReply) -> some View {
        Button {
            onTap(reply)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: reply.icon)
                    .font(.system(size: 12, weight: .semibold))

                Text(reply.label)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Constants.Colors.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Constants.Colors.surfaceGlass)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Constants.Colors.surfaceBorder, lineWidth: Constants.Layout.glassBorderWidth)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Quick reply: \(reply.label)")
        .accessibilityHint("Tap to send, hold to preview")
        .onLongPressGesture(minimumDuration: 0.5) {
            previewReply = reply
        }
        .popover(isPresented: Binding(
            get: { previewReply?.id == reply.id },
            set: { if !$0 { previewReply = nil } }
        )) {
            previewPopover(reply)
        }
    }

    // MARK: - Preview Popover

    private func previewPopover(_ reply: QuickReply) -> some View {
        VStack(spacing: 8) {
            Image(systemName: reply.icon)
                .font(.system(size: 28))
                .foregroundStyle(Constants.Colors.blue500)

            Text(reply.label)
                .font(.system(.headline, weight: .bold))
                .foregroundStyle(Constants.Colors.textPrimary)

            switch reply.type {
            case .text(let message):
                Text("\"\(message)\"")
                    .font(.system(.subheadline))
                    .foregroundStyle(Constants.Colors.textSecondary)
                    .italic()
            case .audioFile(let filename):
                Text(filename)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Constants.Colors.textTertiary)
            }
        }
        .padding(16)
        .frame(minWidth: 160)
        .background(Constants.Colors.cardBackground)
        .presentationCompactAdaptation(.popover)
    }
}
