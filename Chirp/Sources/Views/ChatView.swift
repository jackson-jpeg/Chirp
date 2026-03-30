import SwiftUI
import OSLog

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
    var onSendImage: ((String) -> Void)?
    var onSendFile: ((URL) -> Void)?
    var cicadaService: CICADAService?

    @State private var composedText: String = ""
    @State private var hiddenText: String = ""
    @State private var showCICADAInput: Bool = false
    @State private var revealMessageID: UUID?
    @State private var replyingTo: MeshTextMessage?
    @State private var showScrollToBottom: Bool = false
    @State private var isNearBottom: Bool = true
    @State private var showImagePicker: Bool = false
    @State private var showDocumentPicker: Bool = false
    @State private var imagePickerSource: ImagePickerSource = .library

    private let logger = Logger(subsystem: Constants.subsystem, category: "ChatView")

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

                    // CICADA hidden message overlay
                    if showCICADAInput {
                        CICADAInputOverlay(
                            hiddenText: $hiddenText,
                            coverTextLength: composedText.count,
                            capacity: cicadaService?.capacity(coverLength: composedText.count) ?? 0,
                            onSend: sendMessage,
                            onDismiss: {
                                withAnimation(.spring(response: Constants.Animations.springResponse, dampingFraction: Constants.Animations.springDamping)) {
                                    showCICADAInput = false
                                    hiddenText = ""
                                }
                            }
                        )
                    }

                    // Input bar
                    ChatInputBar(
                        text: $composedText,
                        replyingTo: replyingTo,
                        onSend: sendMessage,
                        onDismissReply: { replyingTo = nil },
                        onShareLocation: onShareLocation,
                        onTakePhoto: {
                            imagePickerSource = .camera
                            showImagePicker = true
                        },
                        onPickPhoto: {
                            imagePickerSource = .library
                            showImagePicker = true
                        },
                        onPickDocument: onSendFile != nil ? {
                            showDocumentPicker = true
                        } : nil,
                        onLongPressSend: cicadaService?.isEnabled == true ? {
                            withAnimation(.spring(response: Constants.Animations.springResponse, dampingFraction: Constants.Animations.springDamping)) {
                                showCICADAInput.toggle()
                                if !showCICADAInput { hiddenText = "" }
                            }
                        } : nil
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
        .background(Constants.Colors.backgroundPrimary)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showScrollToBottom)
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView(source: imagePickerSource) { image in
                sendImage(image)
            }
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPickerView { url in
                onSendFile?(url)
            }
        }
        .overlay {
            if let revealID = revealMessageID,
               let message = findMessage(id: revealID),
               let hidden = cicadaService?.hiddenText(for: message.id) {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture { revealMessageID = nil }

                    CICADARevealView(
                        hiddenText: hidden,
                        onDismiss: { revealMessageID = nil }
                    )
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: Constants.Animations.quickFade), value: revealMessageID)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(Constants.Colors.textTertiary)

            Text("No messages yet")
                .font(Constants.Typography.cardTitle)
                .foregroundStyle(Constants.Colors.textTertiary)

            Text("Send the first chirp to get the conversation started.")
                .font(Constants.Typography.caption)
                .foregroundStyle(Constants.Colors.textTertiary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

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
                            replyToMessage: replyTo,
                            hasHiddenContent: cicadaService?.hasHiddenContent(message.text) ?? false,
                            onRevealHidden: {
                                revealMessageID = message.id
                            }
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
            .font(Constants.Typography.monoSmall)
            .foregroundStyle(Constants.Colors.textTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Constants.Colors.surfaceGlass)
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

        var textToSend = trimmed

        // Encode hidden message via CICADA if active
        if showCICADAInput && !hiddenText.isEmpty,
           let encoded = cicadaService?.encodeText(cover: trimmed, hidden: hiddenText, channelID: channelID) {
            textToSend = encoded
        }

        HapticsManager.shared.pttUp()
        onSend(textToSend, replyingTo?.id)
        composedText = ""
        hiddenText = ""
        showCICADAInput = false
        replyingTo = nil
        isNearBottom = true
        showScrollToBottom = false
    }

    /// Compress, base64-encode, and send an image through the mesh.
    private func sendImage(_ image: UIImage) {
        guard let compressed = ImageCompressor.compress(image) else {
            logger.error("Image compression failed — not sending")
            return
        }

        let base64 = compressed.base64EncodedString()
        let payload = MeshTextMessage.imagePrefix + base64

        guard payload.count <= MeshTextMessage.maxImagePayloadLength else {
            logger.error("Image payload too large: \(payload.count) characters")
            return
        }

        onSendImage?(payload)
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
