import SwiftUI

// MARK: - Particle Field

private struct Particle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var opacity: Double
    var size: CGFloat
    var speed: CGFloat
}

private struct ParticleFieldView: View {
    @State private var particles: [Particle] = []
    @State private var animate = false

    private let particleCount = 40

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { particle in
                    Circle()
                        .fill(Color(hex: 0xFFB800))
                        .frame(width: particle.size, height: particle.size)
                        .opacity(animate ? particle.opacity : particle.opacity * 0.3)
                        .position(
                            x: particle.x * geo.size.width,
                            y: animate
                                ? particle.y * geo.size.height - 40
                                : particle.y * geo.size.height + 40
                        )
                }
            }
            .onAppear {
                particles = (0..<particleCount).map { _ in
                    Particle(
                        x: CGFloat.random(in: 0...1),
                        y: CGFloat.random(in: 0...1),
                        opacity: Double.random(in: 0.05...0.25),
                        size: CGFloat.random(in: 1.5...3.5),
                        speed: CGFloat.random(in: 0.5...1.5)
                    )
                }
                withAnimation(
                    .easeInOut(duration: 6.0)
                    .repeatForever(autoreverses: true)
                ) {
                    animate = true
                }
            }
        }
    }
}

// MARK: - Radio Wave Rings

private struct RadioWaveView: View {
    @State private var ringScales: [CGFloat] = [0.2, 0.2, 0.2, 0.2, 0.2]
    @State private var ringOpacities: [Double] = [0.7, 0.6, 0.5, 0.4, 0.3]
    @State private var iconScale: CGFloat = 0.5
    @State private var iconOpacity: Double = 0.0
    @State private var glowOpacity: Double = 0.0

    var body: some View {
        ZStack {
            // Glow backdrop
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: 0xFFB800).opacity(0.3),
                            Color(hex: 0xFFB800).opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 120
                    )
                )
                .frame(width: 240, height: 240)
                .opacity(glowOpacity)

            // Concentric rings
            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .stroke(
                        Color(hex: 0xFFB800).opacity(ringOpacities[index]),
                        lineWidth: max(2.5 - CGFloat(index) * 0.4, 0.8)
                    )
                    .frame(width: 200, height: 200)
                    .scaleEffect(ringScales[index])
            }

            // Center antenna icon
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(Color(hex: 0xFFB800))
                .scaleEffect(iconScale)
                .opacity(iconOpacity)
        }
        .onAppear {
            // Icon entrance
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.2)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }

            // Glow
            withAnimation(.easeIn(duration: 1.0).delay(0.3)) {
                glowOpacity = 1.0
            }

            // Staggered ring pulses
            for i in 0..<5 {
                let delay = Double(i) * 0.35
                withAnimation(
                    .easeOut(duration: 3.0)
                    .repeatForever(autoreverses: false)
                    .delay(delay)
                ) {
                    ringScales[i] = 1.4
                    ringOpacities[i] = 0.0
                }
            }
        }
    }
}

// MARK: - Shimmer Button

private struct ShimmerButtonView: View {
    let action: () -> Void

    @State private var shimmerOffset: CGFloat = -1.0

    var body: some View {
        Button(action: action) {
            Text("Get Started")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(hex: 0xFFB800))

                        // Shimmer sweep
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.0),
                                        .white.opacity(0.3),
                                        .white.opacity(0.0)
                                    ],
                                    startPoint: UnitPoint(x: shimmerOffset - 0.3, y: 0.5),
                                    endPoint: UnitPoint(x: shimmerOffset + 0.3, y: 0.5)
                                )
                            )
                    }
                )
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: false)
                .delay(1.5)
            ) {
                shimmerOffset = 2.0
            }
        }
    }
}

// MARK: - Typewriter Text

private struct TypewriterText: View {
    let fullText: String
    let delay: Double

    @State private var visibleCount = 0

    var body: some View {
        Text(fullText.prefix(visibleCount))
            .font(.system(.title3, design: .rounded, weight: .medium))
            .foregroundStyle(.secondary)
            .onAppear {
                Task {
                    try? await Task.sleep(for: .seconds(delay))
                    for _ in fullText {
                        try? await Task.sleep(for: .milliseconds(45))
                        withAnimation(.easeOut(duration: 0.05)) {
                            visibleCount += 1
                        }
                    }
                }
            }
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @Environment(AppState.self) private var appState

    @State private var stepsVisible: [Bool] = [false, false, false]
    @State private var buttonVisible = false
    @State private var badgeVisible = false
    @State private var titleOpacity: Double = 0.0
    @State private var titleScale: CGFloat = 0.85

    private let steps: [(icon: String, title: String, description: String)] = [
        ("antenna.radiowaves.left.and.right", "Pair nearby friends", "Find and connect to devices around you using Wi-Fi Aware."),
        ("bubble.left.and.bubble.right.fill", "Create a channel", "Set up a channel for your group to communicate on."),
        ("mic.fill", "Press and talk", "Hold the button to talk. Release to listen. Simple as that.")
    ]

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            // Particle field
            ParticleFieldView()
                .ignoresSafeArea()

            // Content
            VStack(spacing: 0) {
                Spacer()

                // Radio wave animation
                RadioWaveView()
                    .frame(height: 220)
                    .padding(.bottom, 24)

                // Title with glow
                ZStack {
                    // Glow behind text
                    Text("ChirpChirp")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: 0xFFB800))
                        .blur(radius: 20)
                        .opacity(0.5)

                    Text("ChirpChirp")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: 0xFFB800))
                }
                .opacity(titleOpacity)
                .scaleEffect(titleScale)

                // Typewriter tagline
                TypewriterText(fullText: "Talk close. No towers needed.", delay: 0.8)
                    .padding(.top, 6)
                    .frame(height: 28)

                Spacer()
                    .frame(height: 48)

                // Steps
                VStack(spacing: 20) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        stepRow(index: index, step: step)
                            .opacity(stepsVisible[index] ? 1.0 : 0.0)
                            .offset(x: stepsVisible[index] ? 0 : -30)
                    }
                }
                .padding(.horizontal, 32)

                Spacer()

                // Get Started button
                if buttonVisible {
                    ShimmerButtonView {
                        appState.isOnboardingComplete = true
                    }
                    .padding(.horizontal, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // No internet badge
                if badgeVisible {
                    HStack(spacing: 6) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 12, weight: .semibold))
                        Text("No internet required")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Color(hex: 0xFFB800).opacity(0.7))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color(hex: 0xFFB800).opacity(0.1))
                            .overlay(
                                Capsule()
                                    .stroke(Color(hex: 0xFFB800).opacity(0.2), lineWidth: 0.5)
                            )
                    )
                    .padding(.top, 16)
                    .transition(.opacity)
                }

                Spacer()
                    .frame(height: 40)
            }
        }
        .onAppear {
            startAnimations()
        }
    }

    // MARK: - Step Row

    private func stepRow(index: Int, step: (icon: String, title: String, description: String)) -> some View {
        HStack(spacing: 16) {
            ZStack {
                // Circular amber background that fills in
                Circle()
                    .fill(Color(hex: 0xFFB800).opacity(stepsVisible[index] ? 0.2 : 0.0))
                    .frame(width: 50, height: 50)
                    .animation(.easeOut(duration: 0.6).delay(0.2), value: stepsVisible[index])

                Circle()
                    .stroke(Color(hex: 0xFFB800).opacity(0.3), lineWidth: 1.5)
                    .frame(width: 50, height: 50)

                Image(systemName: step.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xFFB800))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.system(.body, weight: .bold))
                    .foregroundStyle(.white)

                Text(step.description)
                    .font(.system(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
    }

    // MARK: - Animations

    private func startAnimations() {
        // Title entrance
        withAnimation(.spring(response: 0.7, dampingFraction: 0.7).delay(0.3)) {
            titleOpacity = 1.0
            titleScale = 1.0
        }

        // Staggered step entrance
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            for i in 0..<3 {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                    stepsVisible[i] = true
                }
                try? await Task.sleep(for: .seconds(0.5))
            }

            // Button slides up
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                buttonVisible = true
            }

            // Badge fades in
            try? await Task.sleep(for: .seconds(0.4))
            withAnimation(.easeOut(duration: 0.5)) {
                badgeVisible = true
            }
        }
    }
}
