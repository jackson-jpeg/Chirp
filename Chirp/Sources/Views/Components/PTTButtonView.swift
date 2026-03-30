import SwiftUI

struct PTTButtonView: View {
    @Binding var pttState: PTTState
    var onPressDown: () -> Void
    var onPressUp: () -> Void

    @State private var isPressed = false

    // Transmit ring animations
    @State private var ring1Scale: CGFloat = 1.0
    @State private var ring1Opacity: Double = 0.0
    @State private var ring2Scale: CGFloat = 1.0
    @State private var ring2Opacity: Double = 0.0
    @State private var ring3Scale: CGFloat = 1.0
    @State private var ring3Opacity: Double = 0.0

    // Receiving ring animations (contract inward)
    @State private var rxRing1Scale: CGFloat = 1.6
    @State private var rxRing1Opacity: Double = 0.0
    @State private var rxRing2Scale: CGFloat = 1.6
    @State private var rxRing2Opacity: Double = 0.0
    @State private var rxRing3Scale: CGFloat = 1.6
    @State private var rxRing3Opacity: Double = 0.0

    // Idle breathing glow
    @State private var breatheScale: CGFloat = 1.0
    @State private var breatheOpacity: Double = 0.3

    // Denied state
    @State private var shakeOffset: CGFloat = 0.0
    @State private var deniedFlash = false

    // Progress ring for transmit duration
    @State private var transmitProgress: CGFloat = 0.0
    @State private var transmitTimer: Timer?

    private let buttonSize: CGFloat = 160

    // MARK: - Computed Properties

    private var primaryColor: Color {
        switch pttState {
        case .idle:
            return Color(hex: 0xFFB800) // Amber
        case .transmitting:
            return Color(hex: 0xFF3B30) // Red
        case .receiving:
            return Color(hex: 0x30D158) // Green
        case .denied:
            return Color(hex: 0xFF3B30) // Red
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

    private var isIdle: Bool {
        if case .idle = pttState { return true }
        return false
    }

    private var isTransmitting: Bool {
        if case .transmitting = pttState { return true }
        return false
    }

    private var isReceiving: Bool {
        if case .receiving = pttState { return true }
        return false
    }

    private var isDenied: Bool {
        if case .denied = pttState { return true }
        return false
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                // --- Idle breathing glow ---
                if isIdle {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(hex: 0xFFB800).opacity(breatheOpacity * 0.5),
                                    Color(hex: 0xFFB800).opacity(0)
                                ],
                                center: .center,
                                startRadius: buttonSize / 3,
                                endRadius: buttonSize * 0.55
                            )
                        )
                        .frame(width: buttonSize + 60, height: buttonSize + 60)
                        .scaleEffect(breatheScale)
                }

                // --- Transmit: expanding radio wave rings ---
                if isTransmitting {
                    transmitRing(scale: ring1Scale, opacity: ring1Opacity, lineWidth: 4)
                    transmitRing(scale: ring2Scale, opacity: ring2Opacity, lineWidth: 3.5)
                    transmitRing(scale: ring3Scale, opacity: ring3Opacity, lineWidth: 3)
                }

                // --- Receiving: contracting wave rings ---
                if isReceiving {
                    receiveRing(scale: rxRing1Scale, opacity: rxRing1Opacity, lineWidth: 3)
                    receiveRing(scale: rxRing2Scale, opacity: rxRing2Opacity, lineWidth: 2.5)
                    receiveRing(scale: rxRing3Scale, opacity: rxRing3Opacity, lineWidth: 2)
                }

                // --- Progress ring (transmit live indicator) ---
                if isTransmitting {
                    Circle()
                        .trim(from: 0, to: transmitProgress)
                        .stroke(
                            primaryColor.opacity(0.9),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: buttonSize + 18, height: buttonSize + 18)
                        .rotationEffect(.degrees(-90))
                }

                // --- Thin ring indicator (always visible) ---
                Circle()
                    .stroke(
                        primaryColor.opacity(isTransmitting ? 0.6 : 0.25),
                        lineWidth: isTransmitting ? 2 : 1.5
                    )
                    .frame(width: buttonSize + 18, height: buttonSize + 18)

                // --- Outer shadow for depth ---
                Circle()
                    .fill(primaryColor.opacity(isTransmitting ? 0.35 : (isReceiving ? 0.25 : 0.2)))
                    .frame(width: buttonSize + 10, height: buttonSize + 10)
                    .blur(radius: isTransmitting ? 30 : (isReceiving ? 24 : 20))
                    .offset(y: isTransmitting ? 8 : 6)

                // --- Main button body: FROSTED LIQUID GLASS ---
                ZStack {
                    // Base layer — dark ring for depth
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: buttonSize + 4, height: buttonSize + 4)

                    // Button face — dark frosted glass base
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.6),
                                    Color.black.opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: buttonSize, height: buttonSize)

                    // Color tint overlay
                    Circle()
                        .fill(primaryColor.opacity(0.1))
                        .frame(width: buttonSize, height: buttonSize)

                    // Outer border — thick machined ring
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    primaryColor.opacity(0.9),
                                    primaryColor.opacity(0.3),
                                    primaryColor.opacity(0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isPressed ? 5 : 4
                        )
                        .frame(width: buttonSize, height: buttonSize)

                    // Inner shadow for depth (dark ring inside)
                    Circle()
                        .stroke(
                            RadialGradient(
                                colors: [
                                    Color.black.opacity(0.4),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: buttonSize / 2 - 15,
                                endRadius: buttonSize / 2
                            ),
                            lineWidth: 12
                        )
                        .frame(width: buttonSize - 10, height: buttonSize - 10)

                    // Top highlight — convex look (increased opacity)
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    primaryColor.opacity(isPressed ? 0.15 : 0.4),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .frame(width: buttonSize - 20, height: buttonSize - 20)

                    // Denied flash overlay
                    if deniedFlash {
                        Circle()
                            .fill(Color.red.opacity(0.7))
                            .frame(width: buttonSize, height: buttonSize)
                    }
                }

                // --- Icon ---
                Image(systemName: iconName)
                    .font(.system(size: 44, weight: .heavy))
                    .foregroundStyle(primaryColor)
                    .shadow(color: primaryColor.opacity(0.8), radius: 12)
                    .shadow(color: primaryColor.opacity(0.3), radius: 4)
            }
            .frame(width: buttonSize + 80, height: buttonSize + 80)
            .scaleEffect(isPressed ? 0.87 : 1.0)
            .offset(x: shakeOffset)
            .animation(.spring(response: 0.15, dampingFraction: 0.55), value: isPressed)
            .allowsHitTesting(canInteract)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Push to talk")
            .accessibilityHint(isTransmitting ? "Release to stop transmitting" : "Hold to transmit voice")
            .accessibilityAddTraits(.startsMediaSession)
            .accessibilityIdentifier(AccessibilityID.pttButton)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard canInteract, !isPressed else { return }
                        isPressed = true
                        HapticsManager.shared.pttDown()
                        SoundEffects.shared.playChirpBegin()
                        onPressDown()
                    }
                    .onEnded { _ in
                        guard isPressed else { return }
                        isPressed = false
                        HapticsManager.shared.pttUp()
                        SoundEffects.shared.playChirpEnd()
                        onPressUp()
                    }
            )

            // --- "HOLD TO TALK" label ---
            if isIdle {
                Text("HOLD TO TALK")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .tracking(4)
                    .foregroundStyle(Color(hex: 0xFFB800).opacity(0.5))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if isTransmitting {
                Text("LIVE")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .tracking(4)
                    .foregroundStyle(Color(hex: 0xFF3B30).opacity(0.8))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if isReceiving {
                Text("RECEIVING")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .tracking(4)
                    .foregroundStyle(Color(hex: 0x30D158).opacity(0.7))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: pttState)
        .onChange(of: pttState) { _, newValue in
            handleStateChange(newValue)
        }
        .onAppear {
            startIdleBreathing()
        }
    }

    // MARK: - Ring Subviews

    @ViewBuilder
    private func transmitRing(scale: CGFloat, opacity: Double, lineWidth: CGFloat) -> some View {
        Circle()
            .stroke(primaryColor.opacity(opacity), lineWidth: lineWidth)
            .frame(width: buttonSize + 20, height: buttonSize + 20)
            .scaleEffect(scale)
    }

    @ViewBuilder
    private func receiveRing(scale: CGFloat, opacity: Double, lineWidth: CGFloat) -> some View {
        Circle()
            .stroke(primaryColor.opacity(opacity), lineWidth: lineWidth)
            .frame(width: buttonSize + 20, height: buttonSize + 20)
            .scaleEffect(scale)
    }

    // MARK: - State Change Handler

    private func handleStateChange(_ newState: PTTState) {
        switch newState {
        case .idle:
            stopTransmitAnimations()
            stopReceiveAnimations()
            startIdleBreathing()

        case .transmitting:
            stopIdleBreathing()
            stopReceiveAnimations()
            startTransmitAnimations()
            startTransmitProgress()

        case .receiving:
            stopIdleBreathing()
            stopTransmitAnimations()
            startReceiveAnimations()

        case .denied:
            stopIdleBreathing()
            stopTransmitAnimations()
            triggerDenied()
        }
    }

    // MARK: - Idle Breathing

    private func startIdleBreathing() {
        breatheScale = 1.0
        breatheOpacity = 0.15
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
            breatheScale = 1.15
            breatheOpacity = 0.7
        }
    }

    private func stopIdleBreathing() {
        withAnimation(.easeOut(duration: 0.2)) {
            breatheScale = 1.0
            breatheOpacity = 0.0
        }
    }

    // MARK: - Transmit Expanding Rings

    private func startTransmitAnimations() {
        // Reset
        ring1Scale = 1.0; ring1Opacity = 0.0
        ring2Scale = 1.0; ring2Opacity = 0.0
        ring3Scale = 1.0; ring3Opacity = 0.0

        // Ring 1 — immediate
        withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
            ring1Scale = 2.3
            ring1Opacity = 0.0
        }
        withAnimation(.easeIn(duration: 0.15)) {
            ring1Opacity = 0.7
        }

        // Ring 2 — 0.35s delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                ring2Scale = 2.3
                ring2Opacity = 0.0
            }
            withAnimation(.easeIn(duration: 0.15)) {
                ring2Opacity = 0.6
            }
        }

        // Ring 3 — 0.7s delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                ring3Scale = 2.3
                ring3Opacity = 0.0
            }
            withAnimation(.easeIn(duration: 0.15)) {
                ring3Opacity = 0.5
            }
        }
    }

    private func stopTransmitAnimations() {
        withAnimation(.easeOut(duration: 0.2)) {
            ring1Scale = 1.0; ring1Opacity = 0.0
            ring2Scale = 1.0; ring2Opacity = 0.0
            ring3Scale = 1.0; ring3Opacity = 0.0
            transmitProgress = 0.0
        }
        transmitTimer?.invalidate()
        transmitTimer = nil
    }

    // MARK: - Transmit Progress Ring

    private func startTransmitProgress() {
        transmitProgress = 0.0
        // Fill the ring over ~30 seconds (arbitrary max transmit time visual)
        transmitTimer?.invalidate()
        transmitTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                let increment: CGFloat = 0.1 / 30.0 // Full ring in 30s
                if transmitProgress < 1.0 {
                    withAnimation(.linear(duration: 0.1)) {
                        transmitProgress = min(transmitProgress + increment, 1.0)
                    }
                }
            }
        }
    }

    // MARK: - Receive Contracting Rings

    private func startReceiveAnimations() {
        // Reset — start large
        rxRing1Scale = 1.8; rxRing1Opacity = 0.0
        rxRing2Scale = 1.8; rxRing2Opacity = 0.0
        rxRing3Scale = 1.8; rxRing3Opacity = 0.0

        // Ring 1 — contract inward
        withAnimation(.easeIn(duration: 1.2).repeatForever(autoreverses: false)) {
            rxRing1Scale = 1.0
            rxRing1Opacity = 0.0
        }
        withAnimation(.easeIn(duration: 0.15)) {
            rxRing1Opacity = 0.6
        }

        // Ring 2 — 0.3s delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeIn(duration: 1.2).repeatForever(autoreverses: false)) {
                rxRing2Scale = 1.0
                rxRing2Opacity = 0.0
            }
            withAnimation(.easeIn(duration: 0.15)) {
                rxRing2Opacity = 0.5
            }
        }

        // Ring 3 — 0.6s delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeIn(duration: 1.2).repeatForever(autoreverses: false)) {
                rxRing3Scale = 1.0
                rxRing3Opacity = 0.0
            }
            withAnimation(.easeIn(duration: 0.15)) {
                rxRing3Opacity = 0.4
            }
        }
    }

    private func stopReceiveAnimations() {
        withAnimation(.easeOut(duration: 0.2)) {
            rxRing1Scale = 1.6; rxRing1Opacity = 0.0
            rxRing2Scale = 1.6; rxRing2Opacity = 0.0
            rxRing3Scale = 1.6; rxRing3Opacity = 0.0
        }
    }

    // MARK: - Denied Animation

    private func triggerDenied() {
        HapticsManager.shared.denied()

        // Flash red hard
        deniedFlash = true
        withAnimation(.easeOut(duration: 0.3)) {
            deniedFlash = false
        }

        // Aggressive shake — more dramatic than before
        let shakeSequence: [(CGFloat, Double)] = [
            (14, 0.0),
            (-12, 0.06),
            (10, 0.12),
            (-8, 0.18),
            (5, 0.24),
            (-3, 0.30),
            (0, 0.36)
        ]

        for (offset, delay) in shakeSequence {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.06, dampingFraction: 0.25)) {
                    shakeOffset = offset
                }
            }
        }
    }
}
