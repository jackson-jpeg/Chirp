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
            .foregroundStyle(Constants.Colors.amber)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .opacity(0.7)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Constants.Colors.amber.opacity(0.25), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
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
                .foregroundStyle(Constants.Colors.amber)

            Text(reply.label)
                .font(.system(.headline, weight: .bold))
                .foregroundStyle(.white)

            switch reply.type {
            case .text(let message):
                Text("\"\(message)\"")
                    .font(.system(.subheadline))
                    .foregroundStyle(.white.opacity(0.6))
                    .italic()
            case .audioFile(let filename):
                Text(filename)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(16)
        .frame(minWidth: 160)
        .background(.ultraThinMaterial)
        .presentationCompactAdaptation(.popover)
    }
}
