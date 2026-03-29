import SwiftUI

enum ToastType {
    case info
    case success
    case warning
    case error

    var color: Color {
        switch self {
        case .info:
            return Color(hex: 0x0A84FF)
        case .success:
            return Color(hex: 0x30D158)
        case .warning:
            return Color(hex: 0xFFB800)
        case .error:
            return Color(hex: 0xFF3B30)
        }
    }

    var icon: String {
        switch self {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.circle.fill"
        }
    }
}

struct ChirpToastView: View {
    let message: String
    let type: ToastType
    let duration: TimeInterval
    var onDismiss: () -> Void = {}

    @State private var isVisible = false
    @State private var dragOffset: CGFloat = 0
    @State private var progress: CGFloat = 0.0

    init(message: String, type: ToastType, duration: TimeInterval = 3.0, onDismiss: @escaping () -> Void = {}) {
        self.message = message
        self.type = type
        self.duration = duration
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack {
            if isVisible {
                toastContent
                    .offset(y: dragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if value.translation.height < 0 {
                                    dragOffset = value.translation.height
                                }
                            }
                            .onEnded { value in
                                if value.translation.height < -30 {
                                    dismiss()
                                } else {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        dragOffset = 0
                                    }
                                }
                            }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                isVisible = true
            }

            // Start progress bar animation
            withAnimation(.linear(duration: duration)) {
                progress = 1.0
            }

            // Auto-dismiss
            Task {
                try? await Task.sleep(for: .seconds(duration))
                dismiss()
            }
        }
    }

    // MARK: - Toast Content

    private var toastContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Icon with color
                Image(systemName: type.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(type.color)
                    .shadow(color: type.color.opacity(0.4), radius: 4)

                // Message
                Text(message)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Spacer(minLength: 4)

                // Close button
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .accessibilityLabel("Dismiss notification")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            // Progress bar at bottom
            GeometryReader { geometry in
                Rectangle()
                    .fill(type.color.opacity(0.5))
                    .frame(
                        width: geometry.size.width * (1.0 - progress),
                        height: 2
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 2)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    type.color.opacity(0.3),
                                    Color.white.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
                .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    // MARK: - Dismiss

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.25)) {
            isVisible = false
        }
        Task {
            try? await Task.sleep(for: .seconds(0.25))
            onDismiss()
        }
    }
}

// MARK: - Toast Modifier

struct ToastModifier: ViewModifier {
    @Binding var toast: ToastItem?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast {
                ChirpToastView(
                    message: toast.message,
                    type: toast.type
                ) {
                    self.toast = nil
                }
                .padding(.top, 8)
            }
        }
    }
}

struct ToastItem: Equatable {
    let id = UUID()
    let message: String
    let type: ToastType

    static func == (lhs: ToastItem, rhs: ToastItem) -> Bool {
        lhs.id == rhs.id
    }
}

extension View {
    func chirpToast(_ toast: Binding<ToastItem?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}
