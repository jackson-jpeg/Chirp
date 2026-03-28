import SwiftUI

enum ToastType {
    case info
    case success
    case warning
    case error

    var color: Color {
        switch self {
        case .info:
            return Color(hex: 0xFFB800)
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
    var onDismiss: () -> Void = {}

    @State private var isVisible = false

    var body: some View {
        VStack {
            if isVisible {
                HStack(spacing: 10) {
                    Image(systemName: type.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(type.color)

                    Text(message)
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(.white)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(type.color.opacity(0.3), lineWidth: 0.5)
                        )
                )
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isVisible = true
            }

            Task {
                try? await Task.sleep(for: .seconds(3))
                withAnimation(.easeOut(duration: 0.3)) {
                    isVisible = false
                }
                try? await Task.sleep(for: .seconds(0.3))
                onDismiss()
            }
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
