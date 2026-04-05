import SwiftUI
import OSLog

/// Full chat interface for a channel with iMessage/Signal-style layout.
///
/// Messages from self appear on the right in amber bubbles; messages from
/// others appear on the left in dark gray bubbles. Consecutive messages
/// from the same sender cluster together with fused bubble corners.
/// Date separators show between day boundaries and large time gaps.
struct ChatView: View {

    let channelID: String
    let localPeerID: String
    let localPeerName: String
    let messages: [MeshTextMessage]
    var onSend: (String, UUID?) -> Void
    var onShareLocation: () -> Void
    var onSendImage: ((String) -> Void)?
    var onSendFile: ((URL) -> Void)?
    var onSendReaction: ((String, UUID) -> Void)?
    var cicadaService: CICADAService?
    /// Typing peers for the current channel.
    var typingPeers: Set<String> = []
    /// Called when the user starts/continues typing (debounced by caller).
    var onTyping: (() -> Void)?
    /// Called when a non-self message appears on screen (for read receipts).
    var onMessageAppeared: ((UUID) -> Void)?
    /// Called when a voice note is recorded: (duration, audioData).
    var onSendVoiceNote: ((TimeInterval, Data) -> Void)?

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
    @State private var reactingToMessageID: UUID?

    // Search state
    @State private var searchText: String = ""
    @State private var isSearching: Bool = false
    @State private var currentSearchIndex: Int = 0

    private let logger = Logger(subsystem: Constants.subsystem, category: "ChatView")

    // MARK: - Body

    /// Messages matching the current search query.
    private var searchResults: [UUID] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.lowercased()
        return messages.filter { $0.text.lowercased().contains(query) }.map(\.id)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    // Search bar
                    if isSearching {
                        searchBar(proxy: proxy)
                    }

                    // Messages list
                    if messages.isEmpty && searchText.isEmpty {
                        emptyState
                    } else {
                        messagesList(proxy: proxy)
                    }

                    // Typing indicator
                    if !typingPeers.isEmpty {
                        typingIndicatorView
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
                        } : nil,
                        onTyping: onTyping,
                        onSendVoiceNote: onSendVoiceNote
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
        .animation(.easeInOut(duration: 0.2), value: typingPeers.isEmpty)
        .animation(.easeInOut(duration: 0.2), value: isSearching)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation { isSearching.toggle() }
                    if !isSearching { searchText = ""; currentSearchIndex = 0 }
                } label: {
                    Image(systemName: isSearching ? "xmark" : "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Constants.Colors.textSecondary)
                }
                .accessibilityLabel(isSearching ? "Close search" : "Search messages")
            }
        }
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
        VStack(spacing: 16) {
            Spacer()

            // Breathing speech bubble icon
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Constants.Colors.amber.opacity(0.6), Constants.Colors.amber.opacity(0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .symbolEffect(.pulse, options: .repeating)

            Text(String(localized: "chat.empty.title"))
                .font(Constants.Typography.cardTitle)
                .foregroundStyle(Constants.Colors.textSecondary)

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(String(localized: "chat.empty.encrypted"))
                    .font(Constants.Typography.caption)
            }
            .foregroundStyle(Constants.Colors.textTertiary.opacity(0.7))

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(String(localized: "chat.empty.accessibility"))
    }

    // MARK: - Messages List

    private func messagesList(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(Array(clusteredMessages.enumerated()), id: \.offset) { _, item in
                    switch item {
                    case .dateSeparator(let date):
                        dateSeparator(for: date)
                            .padding(.vertical, 6)

                    case .message(let message, let position):
                        let isFromSelf = message.senderID == localPeerID
                        let replyTo = findMessage(id: message.replyToID)

                        MessageBubbleView(
                            message: message,
                            isFromSelf: isFromSelf,
                            replyToMessage: replyTo,
                            hasHiddenContent: cicadaService?.hasHiddenContent(message.text) ?? false,
                            onRevealHidden: {
                                revealMessageID = message.id
                            },
                            clusterPosition: position,
                            onSwipeReply: {
                                replyingTo = message
                            },
                            searchHighlight: searchText
                        )
                        .id(message.id)
                        .padding(.horizontal, 8)
                        .onAppear {
                            // Send read receipt for non-self messages
                            if !isFromSelf {
                                onMessageAppeared?(message.id)
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.95).combined(with: .opacity),
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

                            Menu {
                                ForEach(reactionEmojis, id: \.self) { emoji in
                                    Button(emoji) {
                                        onSendReaction?(emoji, message.id)
                                        HapticsManager.shared.pttUp()
                                    }
                                }
                            } label: {
                                Label("React", systemImage: "face.smiling")
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
            proxy.scrollTo("bottom", anchor: .bottom)
        }
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 30 {
                        isNearBottom = false
                        if messages.count > 5 {
                            showScrollToBottom = true
                        }
                    } else if value.translation.height < -10 {
                        isNearBottom = true
                        showScrollToBottom = false
                    }
                }
        )
    }

    // MARK: - Search Bar

    private func searchBar(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(Constants.Colors.textTertiary)

                TextField(String(localized: "chat.search.placeholder"), text: $searchText)
                    .font(Constants.Typography.body)
                    .foregroundStyle(Constants.Colors.textPrimary)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Search messages")
                    .accessibilityIdentifier(AccessibilityID.chatSearchField)

                if !searchText.isEmpty {
                    // Result count + navigation
                    if !searchResults.isEmpty {
                        Text("\(currentSearchIndex + 1) of \(searchResults.count)")
                            .font(Constants.Typography.monoSmall)
                            .foregroundStyle(Constants.Colors.textSecondary)

                        Button {
                            navigateSearch(direction: -1, proxy: proxy)
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Constants.Colors.textSecondary)
                        }
                        .accessibilityLabel("Previous search result")

                        Button {
                            navigateSearch(direction: 1, proxy: proxy)
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Constants.Colors.textSecondary)
                        }
                        .accessibilityLabel("Next search result")
                    } else {
                        Text(String(localized: "chat.search.noResults"))
                            .font(Constants.Typography.monoSmall)
                            .foregroundStyle(Constants.Colors.textTertiary)
                    }

                    Button {
                        searchText = ""
                        currentSearchIndex = 0
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Constants.Colors.textTertiary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Constants.Colors.surfaceGlass)

            Rectangle()
                .fill(Constants.Colors.surfaceBorder)
                .frame(height: Constants.Layout.glassBorderWidth)
        }
        .onChange(of: searchText) { _, _ in
            currentSearchIndex = 0
            if let first = searchResults.first {
                withAnimation {
                    proxy.scrollTo(first, anchor: .center)
                }
            }
        }
    }

    private func navigateSearch(direction: Int, proxy: ScrollViewProxy) {
        guard !searchResults.isEmpty else { return }
        currentSearchIndex = (currentSearchIndex + direction + searchResults.count) % searchResults.count
        withAnimation {
            proxy.scrollTo(searchResults[currentSearchIndex], anchor: .center)
        }
    }

    // MARK: - Typing Indicator

    private var typingIndicatorView: some View {
        HStack(spacing: 8) {
            // Bouncing dots
            TypingDotsView()

            let names = Array(typingPeers.sorted())
            if names.count == 1 {
                Text(String(localized: "chat.typing.one \(names[0])"))
                    .font(Constants.Typography.caption)
                    .foregroundStyle(Constants.Colors.textTertiary)
            } else if names.count == 2 {
                Text(String(localized: "chat.typing.two \(names[0]) \(names[1])"))
                    .font(Constants.Typography.caption)
                    .foregroundStyle(Constants.Colors.textTertiary)
            } else {
                Text(String(localized: "chat.typing.many \(names.count)"))
                    .font(Constants.Typography.caption)
                    .foregroundStyle(Constants.Colors.textTertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityLabel("\(typingPeers.joined(separator: ", ")) typing")
        .accessibilityIdentifier(AccessibilityID.chatTypingIndicator)
    }

    // MARK: - Scroll-to-Bottom FAB

    /// Count of messages that arrived while scrolled up.
    private var newMessagesSinceScroll: Int {
        // Approximate: count messages from non-self senders at the tail
        let recentSelf = messages.last?.senderID == localPeerID
        guard !recentSelf else { return 0 }
        var count = 0
        for msg in messages.reversed() {
            if msg.senderID != localPeerID {
                count += 1
            } else {
                break
            }
        }
        return min(count, 99)
    }

    private func scrollToBottomButton(proxy: ScrollViewProxy) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            showScrollToBottom = false
            isNearBottom = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .strokeBorder(Constants.Colors.surfaceBorder, lineWidth: 0.5)
                    )
                    .overlay(
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Constants.Colors.amber)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)

                // New message count badge
                if newMessagesSinceScroll > 0 {
                    Text("\(newMessagesSinceScroll)")
                        .font(Constants.Typography.badge)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Constants.Colors.hotRed)
                        )
                        .offset(x: 4, y: -4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .accessibilityLabel(newMessagesSinceScroll > 0
            ? String(localized: "chat.scrollToBottom.withNew \(newMessagesSinceScroll)")
            : String(localized: "chat.scrollToBottom")
        )
    }

    // MARK: - Date Separator

    private func dateSeparator(for date: Date) -> some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Constants.Colors.surfaceBorder)
                .frame(height: 0.5)

            Text(formattedDateSeparator(date))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Constants.Colors.textTertiary)
                .fixedSize()

            Rectangle()
                .fill(Constants.Colors.surfaceBorder)
                .frame(height: 0.5)
        }
        .padding(.horizontal, 24)
        .accessibilityLabel("Messages from \(formattedDateSeparator(date))")
    }

    // MARK: - Message Clustering

    /// Clusters consecutive messages from the same sender and inserts date separators.
    private var clusteredMessages: [ChatItem] {
        guard !messages.isEmpty else { return [] }

        var items: [ChatItem] = []
        let calendar = Calendar.current

        var previousDate: Date?

        // Group consecutive messages by same sender
        var i = 0
        while i < messages.count {
            let message = messages[i]

            // Insert date separator for new days or large time gaps (>15 min)
            if let prev = previousDate {
                let gap = message.timestamp.timeIntervalSince(prev)
                if !calendar.isDate(message.timestamp, inSameDayAs: prev) || gap > 900 {
                    items.append(.dateSeparator(message.timestamp))
                }
            } else {
                items.append(.dateSeparator(message.timestamp))
            }

            // Collect cluster of consecutive messages from same sender (within 2 min)
            var cluster: [MeshTextMessage] = [message]
            var j = i + 1
            while j < messages.count,
                  messages[j].senderID == message.senderID {
                guard let lastMessage = cluster.last else { break }
                guard messages[j].timestamp.timeIntervalSince(lastMessage.timestamp) < 120 else { break }
                cluster.append(messages[j])
                j += 1
            }

            // Assign cluster positions
            if cluster.count == 1 {
                items.append(.message(cluster[0], .solo))
            } else {
                for (idx, msg) in cluster.enumerated() {
                    let position: MessageBubbleView.ClusterPosition
                    if idx == 0 {
                        position = .first
                    } else if idx == cluster.count - 1 {
                        position = .last
                    } else {
                        position = .middle
                    }
                    items.append(.message(msg, position))
                }
            }

            previousDate = cluster.last?.timestamp
            i = j
        }

        return items
    }

    // MARK: - Reactions

    private let reactionEmojis = ["\u{1F44D}", "\u{2764}\u{FE0F}", "\u{1F602}", "\u{1F62E}", "\u{1F622}", "\u{1F525}"]

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
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Chat Item

private enum ChatItem {
    case dateSeparator(Date)
    case message(MeshTextMessage, MessageBubbleView.ClusterPosition)
}

// MARK: - Typing Dots Animation

/// Three bouncing dots with staggered animation for typing indicators.
struct TypingDotsView: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Constants.Colors.textTertiary)
                    .frame(width: 5, height: 5)
                    .offset(y: animate ? -3 : 0)
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}
