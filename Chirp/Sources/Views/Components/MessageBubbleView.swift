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

    // MARK: - Body

    var body: some View {
        HStack {
            if isFromSelf { Spacer(minLength: 60) }

            VStack(alignment: isFromSelf ? .trailing : .leading, spacing: 2) {
                // Sender name (others only)
                if !isFromSelf {
                    Text(message.senderName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
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
                                .font(.system(.body, weight: .regular))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                        } else {
                            attachmentBadge(attachment)
                            Text(message.text)
                                .font(.system(.body, weight: .regular))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                        }
                    } else {
                        // Plain text message
                        Text(message.text)
                            .font(.system(.body, weight: .regular))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                    }

                    // Timestamp
                    Text(formattedTime)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
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
                .fill(Constants.Colors.amber.opacity(0.6))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 1) {
                Text(reply.senderName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Constants.Colors.amber.opacity(0.8))

                Text(reply.text)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
            }
        }
        .padding(6)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Attachment Badge

    private func attachmentBadge(_ type: MeshTextMessage.AttachmentType) -> some View {
        HStack(spacing: 4) {
            Image(systemName: attachmentIcon(type))
                .font(.system(size: 11, weight: .semibold))
            Text(attachmentLabel(type))
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(Constants.Colors.amber)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Constants.Colors.amber.opacity(0.15))
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
            ? Constants.Colors.amber.opacity(0.85)
            : Color.white.opacity(0.1)
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
