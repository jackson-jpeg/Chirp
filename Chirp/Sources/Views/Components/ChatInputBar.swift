import SwiftUI
import AVFoundation

/// The message composition bar at the bottom of the chat view.
///
/// Features a text field, send button, attachment menu, character counter,
/// and an optional reply preview that can be dismissed.
struct ChatInputBar: View {

    @Binding var text: String
    let replyingTo: MeshTextMessage?
    var onSend: () -> Void
    var onDismissReply: () -> Void
    var onShareLocation: () -> Void
    var onTakePhoto: (() -> Void)?
    var onPickPhoto: (() -> Void)?
    var onPickDocument: (() -> Void)?
    var onLongPressSend: (() -> Void)?
    /// Called when user starts/continues typing (for typing indicators).
    var onTyping: (() -> Void)?
    /// Called when a voice note is recorded: (duration, audioData).
    var onSendVoiceNote: ((TimeInterval, Data) -> Void)?

    @FocusState private var isTextFieldFocused: Bool
    @State private var isRecordingVoice: Bool = false
    @State private var voiceRecordingDuration: TimeInterval = 0
    @State private var voiceRecordingTimer: Timer?
    @State private var audioRecorder: VoiceNoteRecorder?
    @State private var dragOffset: CGFloat = 0

    private let maxCharacters = MeshTextMessage.maxTextLength
    private let characterWarningThreshold = 800

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Reply preview
            if let reply = replyingTo {
                replyBanner(reply)
            }

            // Voice recording overlay
            if isRecordingVoice {
                voiceRecordingOverlay
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }

            // Input row
            HStack(alignment: .bottom, spacing: 8) {
                // Attachment menu
                attachmentMenu

                // Text input area
                VStack(alignment: .trailing, spacing: 2) {
                    TextField("Message", text: $text, axis: .vertical)
                        .font(Constants.Typography.body)
                        .foregroundStyle(Constants.Colors.textPrimary)
                        .lineLimit(1...5)
                        .focused($isTextFieldFocused)
                        .onChange(of: text) { _, newValue in
                            // Enforce max length
                            if newValue.count > maxCharacters {
                                text = String(newValue.prefix(maxCharacters))
                            }
                            // Notify typing indicator
                            if !newValue.isEmpty {
                                onTyping?()
                            }
                        }
                        .accessibilityLabel(String(localized: "accessibility.messageInput"))
                        .accessibilityIdentifier(AccessibilityID.chatInputField)

                    // Character counter (always visible, opacity increases near limit)
                    Text("\(text.count)/\(maxCharacters)")
                        .font(Constants.Typography.badge)
                        .foregroundStyle(text.count >= 950 ? Constants.Colors.hotRed : Constants.Colors.textTertiary)
                        .opacity(text.count >= 950 ? 1.0 : (text.count >= characterWarningThreshold ? 0.6 : 0.3))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Constants.Colors.surfaceGlass)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            isTextFieldFocused
                                ? Constants.Colors.amber.opacity(0.5)
                                : Constants.Colors.surfaceBorder,
                            lineWidth: isTextFieldFocused ? 1.5 : Constants.Layout.glassBorderWidth
                        )
                )
                .shadow(
                    color: isTextFieldFocused ? Constants.Colors.amber.opacity(0.15) : .clear,
                    radius: 8
                )
                .animation(.easeInOut(duration: 0.2), value: isTextFieldFocused)

                // Send button
                sendButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(
            Rectangle()
                .fill(Constants.Colors.backgroundPrimary)
                .overlay(
                    Rectangle()
                        .fill(Constants.Colors.surfaceBorder)
                        .frame(height: Constants.Layout.glassBorderWidth),
                    alignment: .top
                )
                .ignoresSafeArea(edges: .bottom)
        )
        .animation(.easeInOut(duration: 0.15), value: replyingTo?.id)
        .animation(.easeInOut(duration: 0.15), value: text.count)
    }

    // MARK: - Reply Banner

    private func replyBanner(_ reply: MeshTextMessage) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Constants.Colors.blue500)
                .frame(width: 3, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("Replying to \(reply.senderName)")
                    .font(Constants.Typography.monoSmall)
                    .foregroundStyle(Constants.Colors.blue500)

                Text(reply.text)
                    .font(Constants.Typography.caption)
                    .foregroundStyle(Constants.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                onDismissReply()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Constants.Colors.textTertiary)
            }
            .accessibilityLabel(String(localized: "accessibility.dismissReply"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Constants.Colors.surfaceGlass)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Attachment Menu

    private var attachmentMenu: some View {
        Menu {
            Button {
                onShareLocation()
            } label: {
                Label("Share Location", systemImage: "location.fill")
            }

            if let onTakePhoto {
                Button {
                    onTakePhoto()
                } label: {
                    Label("Take Photo", systemImage: "camera.fill")
                }
            }

            if let onPickPhoto {
                Button {
                    onPickPhoto()
                } label: {
                    Label("Send Photo", systemImage: "photo.fill")
                }
            }

            if let onPickDocument {
                Button {
                    onPickDocument()
                } label: {
                    Label("Send Document", systemImage: "doc.fill")
                }
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Constants.Colors.textTertiary)
                .frame(width: 36, height: 36)
        }
        .accessibilityLabel(String(localized: "accessibility.attachments"))
        .accessibilityIdentifier(AccessibilityID.chatAttachmentMenu)
    }

    // MARK: - Send Button / Mic Button

    private var sendButton: some View {
        let canSend = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return Group {
            if canSend {
                Button {
                    onSend()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Constants.Colors.slate900)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Constants.Colors.amber)
                        )
                        .shadow(color: Constants.Colors.amber.opacity(0.4), radius: 6, y: 2)
                }
                .transition(.scale(scale: 0.5).combined(with: .opacity))
                .accessibilityLabel(String(localized: "accessibility.sendMessage"))
                .accessibilityHint(String(localized: "accessibility.sendMessage.hint"))
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            onLongPressSend?()
                        }
                )
                .accessibilityIdentifier(AccessibilityID.chatSendButton)
            } else if onSendVoiceNote != nil {
                // Mic button for voice notes (hold to record)
                micButton
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            } else {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Constants.Colors.textTertiary.opacity(0.4))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Constants.Colors.surfaceGlass)
                    )
                    .accessibilityLabel(String(localized: "accessibility.sendMessage"))
                    .accessibilityHint(String(localized: "accessibility.sendMessage.disabledHint"))
                    .accessibilityIdentifier(AccessibilityID.chatSendButton)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: canSend)
    }

    // MARK: - Voice Note Recording

    private var micButton: some View {
        ZStack {
            Image(systemName: isRecordingVoice ? "mic.fill" : "mic.circle.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(isRecordingVoice ? Constants.Colors.hotRed : Constants.Colors.textTertiary)
                .scaleEffect(isRecordingVoice ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isRecordingVoice)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isRecordingVoice {
                        startRecording()
                    }
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    if value.translation.width < -80 {
                        // Swipe left to cancel
                        cancelRecording()
                    } else {
                        finishRecording()
                    }
                    dragOffset = 0
                }
        )
        .accessibilityLabel(String(localized: "accessibility.recordVoiceNote"))
        .accessibilityHint(String(localized: "accessibility.recordVoiceNote.hint"))
        .accessibilityIdentifier(AccessibilityID.chatVoiceNoteButton)
    }

    // MARK: - Voice Recording Overlay

    private var voiceRecordingOverlay: some View {
        HStack(spacing: 12) {
            // Red recording dot
            Circle()
                .fill(Constants.Colors.hotRed)
                .frame(width: 10, height: 10)
                .opacity(voiceRecordingDuration.truncatingRemainder(dividingBy: 1.0) < 0.5 ? 1.0 : 0.4)

            // Duration
            Text(formatDuration(voiceRecordingDuration))
                .font(Constants.Typography.monoStatus)
                .foregroundStyle(Constants.Colors.textPrimary)

            Spacer()

            // Swipe hint
            if dragOffset > -40 {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11))
                    Text("Swipe to cancel")
                        .font(Constants.Typography.caption)
                }
                .foregroundStyle(Constants.Colors.textTertiary)
            } else {
                Text("Release to cancel")
                    .font(Constants.Typography.caption)
                    .foregroundStyle(Constants.Colors.hotRed)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Constants.Colors.surfaceGlass)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private func startRecording() {
        isRecordingVoice = true
        voiceRecordingDuration = 0
        HapticsManager.shared.pttDown()

        let recorder = VoiceNoteRecorder()
        audioRecorder = recorder
        recorder.startRecording()

        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                voiceRecordingDuration += 0.1
            }
        }
        voiceRecordingTimer = timer
    }

    private func finishRecording() {
        guard isRecordingVoice, let recorder = audioRecorder else { return }
        isRecordingVoice = false
        voiceRecordingTimer?.invalidate()
        voiceRecordingTimer = nil
        HapticsManager.shared.pttUp()

        if let data = recorder.stopRecording(), voiceRecordingDuration >= 0.5 {
            onSendVoiceNote?(voiceRecordingDuration, data)
        }
        audioRecorder = nil
    }

    private func cancelRecording() {
        isRecordingVoice = false
        voiceRecordingTimer?.invalidate()
        voiceRecordingTimer = nil
        audioRecorder?.cancelRecording()
        audioRecorder = nil
        HapticsManager.shared.pttUp()
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
