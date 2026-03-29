import SwiftUI

/// Full chat interface for a channel with iMessage-style layout.
///
/// Messages from self appear on the right in amber bubbles; messages from
/// others appear on the left in dark gray bubbles. Timestamps are grouped
/// by time proximity with date separators for gaps greater than 5 minutes.
struct ChatView: View {

    let channelID: String
    let localPeerID: String
    let localPeerName: String
    let messages: [MeshTextMessage]
    var onSend: (String, UUID?) -> Void
    var onShareLocation: () -> Void

    @State private var composedText: String = ""
    @State private var replyingTo: MeshTextMessage?
    @State private var showScrollToBottom: Bool = false
    @State private var isNearBottom: Bool = true

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    // Messages list
                    if messages.isEmpty {
                        emptyState
                    } else {
                        messagesList(proxy: proxy)
                    }

                    // Input bar
                    ChatInputBar(
                        text: $composedText,
                        replyingTo: replyingTo,
                        onSend: sendMessage,
                        onDismissReply: { replyingTo = nil },
                        onShareLocation: onShareLocation
                    )
                }

                // Scroll-to-bottom FAB
                if showScrollToBottom {
                    scrollToBottomButton(proxy: proxy)
                        .padding(.bottom, 80)
                        .padding(.trailing, 16)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .background(Color(hex: 0x0F172A))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showScrollToBottom)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.white.opacity(0.2))

            Text("No messages yet.\nSend the first one!")
                .font(.system(.body, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("No messages yet")
    }

    // MARK: - Messages List

    private func messagesList(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(Array(groupedMessages.enumerated()), id: \.offset) { _, group in
                    // Date separator
                    dateSeparator(for: group.date)

                    ForEach(group.messages) { message in
                        let isFromSelf = message.senderID == localPeerID
                        let replyTo = findMessage(id: message.replyToID)

                        MessageBubbleView(
                            message: message,
                            isFromSelf: isFromSelf,
                            replyToMessage: replyTo
                        )
                        .id(message.id)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .contextMenu {
                            Button {
                                replyingTo = message
                            } label: {
                                Label("Reply", systemImage: "arrowshape.turn.up.left")
                            }

                            Button {
                                UIPasteboard.general.string = message.text
                            } label: {
                                Label("Copy Text", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }

                // Anchor for scrolling to bottom
                Color.clear
                    .frame(height: 1)
                    .id("bottom")
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: messages.count) { oldCount, newCount in
            guard newCount > oldCount else { return }
            let latestMessage = messages.last

            if isNearBottom || latestMessage?.senderID == localPeerID {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            } else {
                showScrollToBottom = true
            }
        }
        .onAppear {
            // Scroll to bottom on first appear
            proxy.scrollTo("bottom", anchor: .bottom)
        }
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    // User is scrolling up — show FAB if needed
                    if value.translation.height > 30 {
                        isNearBottom = false
                        if messages.count > 5 {
                            showScrollToBottom = true
                        }
                    } else if value.translation.height < -10 {
                        // Scrolling down toward bottom
                        isNearBottom = true
                        showScrollToBottom = false
                    }
                }
        )
    }

    // MARK: - Scroll-to-Bottom FAB

    private func scrollToBottomButton(proxy: ScrollViewProxy) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            showScrollToBottom = false
            isNearBottom = true
        } label: {
            Image(systemName: "chevron.down.circle.fill")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(Constants.Colors.amber)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 38, height: 38)
                )
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .accessibilityLabel("Scroll to latest messages")
    }

    // MARK: - Date Separator

    private func dateSeparator(for date: Date) -> some View {
        Text(formattedDateSeparator(date))
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.3))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.05))
            )
            .padding(.vertical, 8)
    }

    // MARK: - Grouping

    /// Groups messages by time proximity (>5 min gap = new group).
    private var groupedMessages: [MessageGroup] {
        guard !messages.isEmpty else { return [] }

        var groups: [MessageGroup] = []
        var currentGroup: [MeshTextMessage] = []
        var currentDate: Date = messages[0].timestamp

        for message in messages {
            if message.timestamp.timeIntervalSince(currentDate) > 300 || currentGroup.isEmpty {
                if !currentGroup.isEmpty {
                    groups.append(MessageGroup(date: currentDate, messages: currentGroup))
                }
                currentGroup = [message]
                currentDate = message.timestamp
            } else {
                currentGroup.append(message)
            }
        }

        if !currentGroup.isEmpty {
            groups.append(MessageGroup(date: currentDate, messages: currentGroup))
        }

        return groups
    }

    // MARK: - Helpers

    private func findMessage(id: UUID?) -> MeshTextMessage? {
        guard let id else { return nil }
        return messages.first { $0.id == id }
    }

    private func sendMessage() {
        let trimmed = composedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSend(trimmed, replyingTo?.id)
        composedText = ""
        replyingTo = nil
        isNearBottom = true
        showScrollToBottom = false
    }

    private func formattedDateSeparator(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Today \(formatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Yesterday \(formatter.string(from: date))"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, h:mm a"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Message Group

private struct MessageGroup {
    let date: Date
    let messages: [MeshTextMessage]
}
