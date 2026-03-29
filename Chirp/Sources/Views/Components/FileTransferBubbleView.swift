import SwiftUI

struct FileTransferBubbleView: View {
    let transfer: TransferProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // File icon + name
            HStack(spacing: 10) {
                Image(systemName: iconForMIME(transfer.mimeType))
                    .font(.system(size: 24))
                    .foregroundStyle(Constants.Colors.amber)
                    .frame(width: 40, height: 40)
                    .background(Constants.Colors.amber.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(transfer.fileName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(formattedSize(transfer.totalBytes))
                        .font(Constants.Typography.monoSmall)
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()
            }

            // Progress bar (only during active transfer)
            if !transfer.isComplete {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: transfer.progress)
                        .tint(Constants.Colors.amber)

                    Text("\(transfer.receivedChunks)/\(transfer.totalChunks) chunks")
                        .font(Constants.Typography.monoSmall)
                        .foregroundStyle(.white.opacity(0.4))
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Constants.Colors.electricGreen)
                    Text(transfer.isOutbound ? "Sent" : "Received")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Constants.Colors.electricGreen)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Constants.Colors.amber.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("File: \(transfer.fileName), \(formattedSize(transfer.totalBytes)), \(transfer.isComplete ? (transfer.isOutbound ? "sent" : "received") : "\(Int(transfer.progress * 100))% complete")")
        .accessibilityIdentifier(AccessibilityID.fileTransferBubble)
    }

    private func iconForMIME(_ mimeType: String) -> String {
        if mimeType.hasPrefix("image/") { return "photo.fill" }
        if mimeType.hasPrefix("audio/") { return "waveform" }
        if mimeType.hasPrefix("video/") { return "film.fill" }
        if mimeType.contains("pdf") { return "doc.fill" }
        return "doc.fill"
    }

    private func formattedSize(_ bytes: UInt64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}
