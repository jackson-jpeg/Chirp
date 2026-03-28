import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState

    @State private var currentStep = 0
    @State private var ringScale1: CGFloat = 0.3
    @State private var ringScale2: CGFloat = 0.3
    @State private var ringScale3: CGFloat = 0.3
    @State private var ringOpacity1: Double = 0.8
    @State private var ringOpacity2: Double = 0.6
    @State private var ringOpacity3: Double = 0.4

    private let steps: [(icon: String, title: String, description: String)] = [
        ("antenna.radiowaves.left.and.right", "Pair nearby friends", "Find and connect to devices around you using Wi-Fi Aware."),
        ("bubble.left.and.bubble.right.fill", "Create a channel", "Set up a channel for your group to communicate on."),
        ("mic.fill", "Press and talk", "Hold the button to talk. Release to listen. Simple as that.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Animated radio wave graphic
            ZStack {
                Circle()
                    .stroke(Color(hex: 0xFFB800).opacity(ringOpacity1), lineWidth: 2)
                    .frame(width: 180, height: 180)
                    .scaleEffect(ringScale1)

                Circle()
                    .stroke(Color(hex: 0xFFB800).opacity(ringOpacity2), lineWidth: 1.5)
                    .frame(width: 180, height: 180)
                    .scaleEffect(ringScale2)

                Circle()
                    .stroke(Color(hex: 0xFFB800).opacity(ringOpacity3), lineWidth: 1)
                    .frame(width: 180, height: 180)
                    .scaleEffect(ringScale3)

                // Center icon
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(Color(hex: 0xFFB800))
            }
            .padding(.bottom, 40)

            // Title
            Text("Chirp")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: 0xFFB800))

            Text("Talk close. No towers needed.")
                .font(.system(.title3, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Spacer()

            // Steps
            VStack(spacing: 24) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(currentStep >= index
                                      ? Color(hex: 0xFFB800).opacity(0.2)
                                      : Color.gray.opacity(0.1))
                                .frame(width: 48, height: 48)

                            Image(systemName: step.icon)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(
                                    currentStep >= index
                                    ? Color(hex: 0xFFB800)
                                    : Color.gray.opacity(0.5)
                                )
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.title)
                                .font(.system(.body, weight: .semibold))
                                .foregroundStyle(
                                    currentStep >= index ? .white : .secondary
                                )

                            Text(step.description)
                                .font(.system(.caption))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()
                    }
                    .opacity(currentStep >= index ? 1.0 : 0.4)
                    .animation(.easeOut(duration: 0.4), value: currentStep)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            // Get Started button
            Button {
                appState.isOnboardingComplete = true
            } label: {
                Text("Get Started")
                    .font(.system(.headline, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(hex: 0xFFB800))
                    )
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .background(Color.black)
        .onAppear {
            startRingAnimation()
            startStepAnimation()
        }
    }

    private func startRingAnimation() {
        withAnimation(.easeOut(duration: 2.5).repeatForever(autoreverses: false)) {
            ringScale1 = 1.2
            ringOpacity1 = 0.0
        }

        withAnimation(.easeOut(duration: 2.5).repeatForever(autoreverses: false).delay(0.6)) {
            ringScale2 = 1.2
            ringOpacity2 = 0.0
        }

        withAnimation(.easeOut(duration: 2.5).repeatForever(autoreverses: false).delay(1.2)) {
            ringScale3 = 1.2
            ringOpacity3 = 0.0
        }
    }

    private func startStepAnimation() {
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            withAnimation { currentStep = 1 }
            try? await Task.sleep(for: .seconds(0.8))
            withAnimation { currentStep = 2 }
            try? await Task.sleep(for: .seconds(0.8))
            withAnimation { currentStep = 3 }
        }
    }
}
