import SwiftUI

/// A single message bubble in the chat view.
///
/// Renders with an iMessage-style layout: sender's messages on the right
/// (amber bubbles), others' messages on the left (dark gray bubbles).
/// Supports reply threading with a quoted preview above the main text.
/// Consecutive messages from the same sender cluster together with fused corners.
struct MessageBubbleView: View {

    let message: MeshTextMessage
    let isFromSelf: Bool
    /// The original message this one replies to, if any.
    let replyToMessage: MeshTextMessage?
    var hasHiddenContent: Bool = false
    var onRevealHidden: (() -> Void)?

    /// Position within a cluster of consecutive messages from the same sender.
    var clusterPosition: ClusterPosition = .solo

    /// Swipe-to-reply callback.
    var onSwipeReply: (() -> Void)?

    /// Search text to highlight within the message body.
    var searchHighlight: String = ""

    enum ClusterPosition {
        case solo       // Only message in cluster
        case first      // First message in cluster
        case middle     // Middle of cluster
        case last       // Last message in cluster
    }

    @State private var swipeOffset: CGFloat = 0

    // MARK: - Body

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isFromSelf {
                Spacer(minLength: 60)
            } else {
                // Avatar — only show for last/solo in cluster
                if clusterPosition == .last || clusterPosition == .solo {
                    senderAvatar
                } else {
                    Color.clear.frame(width: 28, height: 28)
                }
            }

            VStack(alignment: isFromSelf ? .trailing : .leading, spacing: 0) {
                // Sender name — only for first/solo in cluster (others only)
                if !isFromSelf && (clusterPosition == .first || clusterPosition == .solo) {
                    Text(message.senderName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(senderColor)
                        .padding(.leading, 12)
                        .padding(.bottom, 2)
                }

                // Bubble content
                bubbleContent
                    .clipShape(bubbleShape)
                    .overlay(
                        bubbleShape
                            .strokeBorder(
                                isFromSelf ? Constants.Colors.amber.opacity(0.2) : Constants.Colors.surfaceBorder,
                                lineWidth: 0.5
                            )
                    )

                // Reaction badges
                if !message.reactions.isEmpty {
                    reactionBadges
                        .padding(.top, 2)
                        .padding(.horizontal, 4)
                }
            }

            if !isFromSelf {
                Spacer(minLength: 60)
            }
        }
        .offset(x: swipeOffset)
        .gesture(swipeGesture)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Sender Avatar

    private var senderAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [senderColor, senderColor.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(String(message.senderName.prefix(1)).uppercased())
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 28, height: 28)
    }

    // MARK: - Bubble Shape

    private var bubbleShape: UnevenRoundedRectangle {
        let large: CGFloat = 18
        let small: CGFloat = 4

        if isFromSelf {
            switch clusterPosition {
            case .solo:
                return UnevenRoundedRectangle(cornerRadii: .init(topLeading: large, bottomLeading: large, bottomTrailing: small, topTrailing: large))
            case .first:
                return UnevenRoundedRectangle(cornerRadii: .init(topLeading: large, bottomLeading: large, bottomTrailing: small, topTrailing: large))
            case .middle:
                return UnevenRoundedRectangle(cornerRadii: .init(topLeading: large, bottomLeading: large, bottomTrailing: small, topTrailing: small))
            case .last:
                return UnevenRoundedRectangle(cornerRadii: .init(topLeading: large, bottomLeading: large, bottomTrailing: large, topTrailing: small))
            }
        } else {
            switch clusterPosition {
            case .solo:
                return UnevenRoundedRectangle(cornerRadii: .init(topLeading: large, bottomLeading: small, bottomTrailing: large, topTrailing: large))
            case .first:
                return UnevenRoundedRectangle(cornerRadii: .init(topLeading: large, bottomLeading: small, bottomTrailing: large, topTrailing: large))
            case .middle:
                return UnevenRoundedRectangle(cornerRadii: .init(topLeading: small, bottomLeading: small, bottomTrailing: large, topTrailing: large))
            case .last:
                return UnevenRoundedRectangle(cornerRadii: .init(topLeading: small, bottomLeading: large, bottomTrailing: large, topTrailing: large))
            }
        }
    }

    // MARK: - Bubble Content

    private var bubbleContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Reply quote
            if let reply = replyToMessage {
                replyPreview(reply)
            }

            // Attachment or text
            if let attachment = message.attachmentType {
                if attachment == .location {
                    LocationAttachmentView(
                        text: message.text,
                        viewerLocation: nil
                    )
                } else if attachment == .image {
                    ImageAttachmentView(text: message.text)
                } else if attachment == .voiceNote, let audioData = Data(base64Encoded: message.text) {
                    VoiceNoteBubbleView(
                        audioData: audioData,
                        duration: 0, // Duration encoded separately or estimated
                        isFromSelf: isFromSelf,
                        clusterPosition: clusterPosition
                    )
                } else {
                    attachmentBadge(attachment)
                    messageText
                }
            } else {
                messageText
            }

            // Timestamp + hidden content — only for last/solo in cluster
            if clusterPosition == .last || clusterPosition == .solo {
                HStack(spacing: 4) {
                    Spacer()
                    Text(formattedTime)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Constants.Colors.textTertiary.opacity(0.7))

                    if hasHiddenContent {
                        Button(action: { onRevealHidden?() }) {
                            Image(systemName: "eye.slash.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Constants.Colors.glassAmberBorder)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reveal hidden message")
                    }

                    // Delivery indicator for self messages
                    if isFromSelf {
                        deliveryIndicator
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(bubbleBackground)
    }

    // MARK: - Delivery Indicator

    @ViewBuilder
    private var deliveryIndicator: some View {
        switch message.deliveryStatus {
        case .read:
            // Double blue checkmarks — peer read
            HStack(spacing: -3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Constants.Colors.blue500)
        case .delivered:
            // Double gray checkmarks — peer received
            HStack(spacing: -3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Constants.Colors.textTertiary.opacity(0.6))
        case .sent:
            // Single gray checkmark — sent, not yet confirmed
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Constants.Colors.textTertiary.opacity(0.5))
        }
    }

    // MARK: - Message Text

    private var messageText: some View {
        Group {
            if !searchHighlight.isEmpty {
                highlightedText(message.text, highlight: searchHighlight)
            } else {
                Text(message.text)
            }
        }
        .font(.system(size: 16))
        .foregroundStyle(Constants.Colors.textPrimary)
        .multilineTextAlignment(.leading)
    }

    /// Build an attributed text with search matches highlighted.
    private func highlightedText(_ text: String, highlight: String) -> Text {
        let lowercasedText = text.lowercased()
        let lowercasedHighlight = highlight.lowercased()

        guard !highlight.isEmpty, lowercasedText.contains(lowercasedHighlight) else {
            return Text(text)
        }

        var result = Text("")
        var remaining = text[text.startIndex...]

        while let range = remaining.lowercased().range(of: lowercasedHighlight) {
            let startOffset = remaining.distance(from: remaining.startIndex, to: range.lowerBound)
            let matchLength = remaining.distance(from: range.lowerBound, to: range.upperBound)

            let beforeIndex = remaining.index(remaining.startIndex, offsetBy: startOffset)
            let matchStartIndex = beforeIndex
            let matchEndIndex = remaining.index(matchStartIndex, offsetBy: matchLength)

            // Text before match
            if beforeIndex > remaining.startIndex {
                result = result + Text(remaining[remaining.startIndex..<beforeIndex])
            }

            // Highlighted match
            result = result + Text(remaining[matchStartIndex..<matchEndIndex])
                .foregroundColor(Constants.Colors.amber)
                .bold()

            remaining = remaining[matchEndIndex...]
        }

        // Append any remaining text after the last match
        if !remaining.isEmpty {
            result = result + Text(remaining)
        }

        return result
    }

    // MARK: - Reply Preview

    private func replyPreview(_ reply: MeshTextMessage) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Constants.Colors.amber)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 1) {
                Text(reply.senderName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Constants.Colors.amber)

                Text(reply.text)
                    .font(.system(size: 12))
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
                .font(.system(size: 11))
            Text(attachmentLabel(type))
                .font(.system(size: 11, weight: .medium))
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

    // MARK: - Reaction Badges

    /// Groups identical emojis and shows each with a count.
    private var reactionBadges: some View {
        let grouped = Dictionary(grouping: message.reactions, by: \.emoji)
        let sorted = grouped.sorted { $0.value.count > $1.value.count }

        return HStack(spacing: 4) {
            ForEach(sorted, id: \.key) { emoji, reactions in
                HStack(spacing: 2) {
                    Text(emoji)
                        .font(.system(size: 12))
                    if reactions.count > 1 {
                        Text("\(reactions.count)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Constants.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Constants.Colors.surfaceGlass)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Constants.Colors.surfaceBorder, lineWidth: 0.5)
                )
            }
        }
    }

    // MARK: - Swipe to Reply

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 30, coordinateSpace: .local)
            .onChanged { value in
                // Only allow right-to-left swipe
                if value.translation.width < 0 {
                    withAnimation(.interactiveSpring()) {
                        swipeOffset = max(value.translation.width, -60)
                    }
                }
            }
            .onEnded { value in
                if value.translation.width < -40 {
                    onSwipeReply?()
                    HapticsManager.shared.pttUp()
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    swipeOffset = 0
                }
            }
    }

    // MARK: - Styling

    private var bubbleBackground: Color {
        isFromSelf
            ? Constants.Colors.amber.opacity(0.15)
            : Constants.Colors.cardBackground
    }

    private var senderColor: Color {
        let hash = abs(message.senderName.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.75)
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
