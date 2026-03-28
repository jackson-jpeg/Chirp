import SwiftUI

struct PTTButtonView: View {
    @Binding var pttState: PTTState
    var onPressDown: () -> Void
    var onPressUp: () -> Void

    @State private var isPressed = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var waveOpacity: Double = 0.0
    @State private var shakeOffset: CGFloat = 0.0
    @State private var deniedFlash = false

    private let buttonSize: CGFloat = 120

    private var primaryColor: Color {
        switch pttState {
        case .idle:
            return Color(hex: 0xFFB800)
        case .transmitting:
            return Color(hex: 0xFF3B30)
        case .receiving:
            return Color(hex: 0x30D158)
        case .denied:
            return Color(hex: 0xFF3B30)
        }
    }

    private var iconName: String {
        switch pttState {
        case .idle, .transmitting, .denied:
            return "mic.fill"
        case .receiving:
            return "speaker.wave.2.fill"
        }
    }

    private var canInteract: Bool {
        switch pttState {
        case .idle, .transmitting:
            return true
        case .receiving, .denied:
            return false
        }
    }

    var body: some View {
        ZStack {
            // Outer pulse ring (transmitting)
            if pttState == .transmitting {
                Circle()
                    .stroke(primaryColor.opacity(0.3), lineWidth: 2)
                    .frame(width: buttonSize + 40, height: buttonSize + 40)
                    .scaleEffect(pulseScale)
                    .opacity(2.0 - Double(pulseScale))

                Circle()
                    .stroke(primaryColor.opacity(0.2), lineWidth: 1.5)
                    .frame(width: buttonSize + 70, height: buttonSize + 70)
                    .scaleEffect(pulseScale * 0.9)
                    .opacity(2.0 - Double(pulseScale))
            }

            // Receiving glow
            if case .receiving = pttState {
                Circle()
                    .fill(primaryColor.opacity(0.15))
                    .frame(width: buttonSize + 50, height: buttonSize + 50)
                    .blur(radius: 20)
                    .scaleEffect(pulseScale)
            }

            // Shadow base
            Circle()
                .fill(primaryColor.opacity(0.2))
                .frame(width: buttonSize + 8, height: buttonSize + 8)
                .blur(radius: 12)

            // Main button
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            primaryColor.opacity(isPressed ? 0.9 : 0.7),
                            primaryColor.opacity(isPressed ? 0.7 : 0.4),
                            primaryColor.opacity(0.15)
                        ],
                        center: .center,
                        startRadius: 5,
                        endRadius: buttonSize / 2
                    )
                )
                .frame(width: buttonSize, height: buttonSize)
                .overlay(
                    Circle()
                        .stroke(primaryColor, lineWidth: isPressed ? 3 : 2)
                )
                .overlay(
                    // Denied flash overlay
                    Circle()
                        .fill(Color.red.opacity(deniedFlash ? 0.5 : 0))
                )

            // Icon
            Image(systemName: iconName)
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(primaryColor)
                .shadow(color: primaryColor.opacity(0.5), radius: 8)

            // Radio wave lines (transmitting)
            if pttState == .transmitting {
                ForEach(0..<3, id: \.self) { i in
                    RadioWaveArc(index: i)
                        .stroke(primaryColor.opacity(waveOpacity - Double(i) * 0.2), lineWidth: 2)
                        .frame(width: buttonSize + CGFloat(i + 1) * 20,
                               height: buttonSize + CGFloat(i + 1) * 20)
                }
            }
        }
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .offset(x: shakeOffset)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        .allowsHitTesting(canInteract)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard canInteract, !isPressed else { return }
                    isPressed = true
                    onPressDown()
                }
                .onEnded { _ in
                    guard isPressed else { return }
                    isPressed = false
                    onPressUp()
                }
        )
        .onChange(of: pttState) { _, newValue in
            switch newValue {
            case .transmitting:
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulseScale = 1.3
                    waveOpacity = 0.8
                }
            case .receiving:
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulseScale = 1.15
                }
            case .denied:
                triggerDenied()
            case .idle:
                withAnimation(.easeOut(duration: 0.3)) {
                    pulseScale = 1.0
                    waveOpacity = 0.0
                }
            }
        }
    }

    private func triggerDenied() {
        deniedFlash = true
        withAnimation(.default) {
            deniedFlash = false
        }

        // Shake animation
        withAnimation(.spring(response: 0.08, dampingFraction: 0.3)) {
            shakeOffset = 10
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.spring(response: 0.08, dampingFraction: 0.3)) {
                shakeOffset = -8
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.spring(response: 0.08, dampingFraction: 0.3)) {
                shakeOffset = 5
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(.spring(response: 0.1, dampingFraction: 0.5)) {
                shakeOffset = 0
            }
        }
    }
}

// MARK: - Radio Wave Arc Shape

private struct RadioWaveArc: Shape {
    let index: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.addArc(center: center,
                     radius: radius,
                     startAngle: .degrees(-30),
                     endAngle: .degrees(30),
                     clockwise: false)
        return path
    }
}

// MARK: - Color hex extension

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}
