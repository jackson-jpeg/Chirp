import SwiftUI

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

    @FocusState private var isTextFieldFocused: Bool

    private let maxCharacters = MeshTextMessage.maxTextLength
    private let characterWarningThreshold = 800

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Reply preview
            if let reply = replyingTo {
                replyBanner(reply)
            }

            // Input row
            HStack(alignment: .bottom, spacing: 8) {
                // Attachment menu
                attachmentMenu

                // Text input area
                VStack(alignment: .trailing, spacing: 2) {
                    TextField("Message...", text: $text, axis: .vertical)
                        .font(.system(.body, weight: .regular))
                        .foregroundStyle(.white)
                        .lineLimit(1...5)
                        .focused($isTextFieldFocused)
                        .onChange(of: text) { _, newValue in
                            // Enforce max length
                            if newValue.count > maxCharacters {
                                text = String(newValue.prefix(maxCharacters))
                            }
                        }
                        .accessibilityLabel("Message input")

                    // Character counter (visible near limit)
                    if text.count >= characterWarningThreshold {
                        Text("\(text.count)/\(maxCharacters)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(text.count >= maxCharacters ? Constants.Colors.hotRed : .white.opacity(0.4))
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                // Send button
                sendButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
        .animation(.easeInOut(duration: 0.15), value: replyingTo?.id)
        .animation(.easeInOut(duration: 0.15), value: text.count >= characterWarningThreshold)
    }

    // MARK: - Reply Banner

    private func replyBanner(_ reply: MeshTextMessage) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Constants.Colors.amber)
                .frame(width: 3, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("Replying to \(reply.senderName)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Constants.Colors.amber)

                Text(reply.text)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer()

            Button {
                onDismissReply()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .accessibilityLabel("Dismiss reply")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
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
        } label: {
            Image(systemName: "paperclip")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 36, height: 36)
        }
        .accessibilityLabel("Attachments")
    }

    // MARK: - Send Button

    private var sendButton: some View {
        let canSend = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return Button {
            guard canSend else { return }
            onSend()
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(canSend ? Constants.Colors.amber : Color.white.opacity(0.15))
        }
        .disabled(!canSend)
        .accessibilityLabel("Send message")
        .animation(.easeInOut(duration: 0.15), value: canSend)
    }
}
