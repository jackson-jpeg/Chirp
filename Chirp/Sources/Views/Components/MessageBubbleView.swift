import SwiftUI

/// A single message bubble in the chat view.
///
/// Renders with an iMessage-style layout: sender's messages on the right
/// (amber bubbles), others' messages on the left (dark gray bubbles).
/// Supports reply threading with a quoted preview above the main text.
struct MessageBubbleView: View {

    let message: MeshTextMessage
    let isFromSelf: Bool
    /// The original message this one replies to, if any.
    let replyToMessage: MeshTextMessage?
    var hasHiddenContent: Bool = false
    var onRevealHidden: (() -> Void)?

    // MARK: - Body

    var body: some View {
        HStack {
            if isFromSelf { Spacer(minLength: 60) }

            VStack(alignment: isFromSelf ? .trailing : .leading, spacing: 2) {
                // Sender name (others only)
                if !isFromSelf {
                    Text(message.senderName)
                        .font(Constants.Typography.monoSmall)
                        .foregroundStyle(Constants.Colors.textSecondary)
                        .padding(.leading, 8)
                }

                // Bubble
                VStack(alignment: .leading, spacing: 4) {
                    // Reply quote
                    if let reply = replyToMessage {
                        replyPreview(reply)
                    }

                    // Attachment indicator
                    if let attachment = message.attachmentType {
                        if attachment == .location {
                            // Render interactive location view instead of plain text
                            LocationAttachmentView(
                                text: message.text,
                                viewerLocation: nil
                            )
                        } else if attachment == .image {
                            ImageAttachmentView(text: message.text)
                        } else if attachment == .file || attachment == .voiceNote {
                            attachmentBadge(attachment)
                            Text(message.text)
                                .font(Constants.Typography.body)
                                .foregroundStyle(Constants.Colors.textPrimary)
                                .multilineTextAlignment(.leading)
                        } else {
                            attachmentBadge(attachment)
                            Text(message.text)
                                .font(Constants.Typography.body)
                                .foregroundStyle(Constants.Colors.textPrimary)
                                .multilineTextAlignment(.leading)
                        }
                    } else {
                        // Plain text message
                        Text(message.text)
                            .font(Constants.Typography.body)
                            .foregroundStyle(Constants.Colors.textPrimary)
                            .multilineTextAlignment(.leading)
                    }

                    // Timestamp + hidden content indicator
                    HStack(spacing: 4) {
                        Spacer()
                        Text(formattedTime)
                            .font(Constants.Typography.badge)
                            .foregroundStyle(Constants.Colors.textTertiary)

                        if hasHiddenContent {
                            Button(action: { onRevealHidden?() }) {
                                Image(systemName: "eye.slash.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Constants.Colors.glassAmberBorder)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Reveal hidden message")
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius, style: .continuous)
                        .strokeBorder(
                            isFromSelf ? Constants.Colors.amber.opacity(0.3) : Constants.Colors.surfaceBorder,
                            lineWidth: Constants.Layout.glassBorderWidth
                        )
                )
            }

            if !isFromSelf { Spacer(minLength: 60) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Reply Preview

    private func replyPreview(_ reply: MeshTextMessage) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Constants.Colors.amber)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 1) {
                Text(reply.senderName)
                    .font(Constants.Typography.badge)
                    .foregroundStyle(Constants.Colors.amber)

                Text(reply.text)
                    .font(Constants.Typography.monoSmall)
                    .foregroundStyle(Constants.Colors.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(6)
        .background(Constants.Colors.surfaceGlass)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Attachment Badge

    private func attachmentBadge(_ type: MeshTextMessage.AttachmentType) -> some View {
        HStack(spacing: 4) {
            Image(systemName: attachmentIcon(type))
                .font(Constants.Typography.monoSmall)
            Text(attachmentLabel(type))
                .font(Constants.Typography.monoSmall)
        }
        .foregroundStyle(Constants.Colors.amber)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Constants.Colors.glassAmber)
        .clipShape(Capsule())
    }

    private func attachmentIcon(_ type: MeshTextMessage.AttachmentType) -> String {
        switch type {
        case .location: "location.fill"
        case .image: "photo.fill"
        case .contact: "person.crop.circle.fill"
        case .file: "doc.fill"
        case .voiceNote: "waveform"
        }
    }

    private func attachmentLabel(_ type: MeshTextMessage.AttachmentType) -> String {
        switch type {
        case .location: "Location"
        case .image: "Image"
        case .contact: "Contact"
        case .file: "File"
        case .voiceNote: "Voice Note"
        }
    }

    // MARK: - Bubble Background

    private var bubbleBackground: Color {
        isFromSelf
            ? Constants.Colors.amber.opacity(0.15)
            : Constants.Colors.cardBackground
    }

    // MARK: - Formatting

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: message.timestamp)
    }

    private var accessibilityDescription: String {
        let sender = isFromSelf ? "You" : message.senderName
        var desc = "\(sender): \(message.text)"
        if replyToMessage != nil {
            desc = "Reply. " + desc
        }
        return desc
    }
}
