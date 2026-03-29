import SwiftUI

// MARK: - Animated Mesh Gradient Background

private struct MeshGradientBackground: View {
    @State private var phase: CGFloat = 0.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let w = size.width
                let h = size.height

                // Draw layered radial gradients that shift over time
                let centers: [(dx: CGFloat, dy: CGFloat, speed: CGFloat)] = [
                    (0.3, 0.2, 0.4),
                    (0.7, 0.6, 0.3),
                    (0.5, 0.8, 0.5),
                    (0.2, 0.5, 0.35),
                ]

                for (i, c) in centers.enumerated() {
                    let offsetX = sin(t * c.speed + Double(i) * 1.5) * 0.15
                    let offsetY = cos(t * c.speed * 0.8 + Double(i) * 2.0) * 0.12
                    let cx = (c.dx + offsetX) * w
                    let cy = (c.dy + offsetY) * h

                    let colors: [(Color, CGFloat)] = i % 2 == 0
                        ? [
                            (Color(red: 0.08, green: 0.05, blue: 0.25).opacity(0.8), 0),
                            (Color(red: 0.12, green: 0.08, blue: 0.35).opacity(0.4), 0.5),
                            (Color.clear, 1.0),
                        ]
                        : [
                            (Color(red: 0.05, green: 0.08, blue: 0.30).opacity(0.7), 0),
                            (Color(red: 0.10, green: 0.05, blue: 0.28).opacity(0.3), 0.5),
                            (Color.clear, 1.0),
                        ]

                    let gradient = Gradient(stops: colors.map {
                        Gradient.Stop(color: $0.0, location: $0.1)
                    })

                    let radius = max(w, h) * 0.6
                    context.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .radialGradient(
                            gradient,
                            center: CGPoint(x: cx, y: cy),
                            startRadius: 0,
                            endRadius: radius
                        )
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Spring Letter Wordmark

private struct SpringWordmark: View {
    let text: String = "ChirpChirp"
    @State private var letterVisible: [Bool] = Array(repeating: false, count: 10)

    var body: some View {
        HStack(spacing: -2) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, char in
                Text(String(char))
                    .font(.system(size: 60, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(hex: 0xFFB800),
                                Color(hex: 0xFFD060),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .scaleEffect(letterVisible[index] ? 1.0 : 0.0)
                    .opacity(letterVisible[index] ? 1.0 : 0.0)
            }
        }
        .onAppear {
            for i in 0..<text.count {
                withAnimation(
                    .spring(response: 0.5, dampingFraction: 0.55)
                    .delay(Double(i) * 0.05 + 0.3)
                ) {
                    letterVisible[i] = true
                }
            }
        }
    }
}

// MARK: - 3D Radio Wave Rings

private struct PerspectiveRadioWaves: View {
    @State private var ringPhases: [CGFloat] = Array(repeating: 0.3, count: 5)
    @State private var ringOpacities: [Double] = Array(repeating: 0.6, count: 5)

    var body: some View {
        ZStack {
            // Glow
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: 0xFFB800).opacity(0.2),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 5,
                        endRadius: 100
                    )
                )
                .frame(width: 260, height: 140)

            // Concentric rings with perspective tilt
            ForEach(0..<5, id: \.self) { index in
                Ellipse()
                    .stroke(
                        Color(hex: 0xFFB800).opacity(ringOpacities[index]),
                        lineWidth: max(2.5 - CGFloat(index) * 0.3, 0.8)
                    )
                    .frame(width: 200, height: 200)
                    .scaleEffect(ringPhases[index])
                    .rotation3DEffect(.degrees(55), axis: (x: 1, y: 0, z: 0))
            }

            // Center dot
            Circle()
                .fill(Color(hex: 0xFFB800))
                .frame(width: 8, height: 8)
                .shadow(color: Color(hex: 0xFFB800).opacity(0.8), radius: 8)
                .rotation3DEffect(.degrees(55), axis: (x: 1, y: 0, z: 0))
        }
        .onAppear {
            for i in 0..<5 {
                let delay = Double(i) * 0.4
                withAnimation(
                    .easeOut(duration: 2.5)
                    .repeatForever(autoreverses: false)
                    .delay(delay)
                ) {
                    ringPhases[i] = 1.8
                    ringOpacities[i] = 0.0
                }
            }
        }
    }
}

// MARK: - Onboarding Page

private struct OnboardingPage: View {
    let icon: String
    let title: String
    let subtitle: String
    let accentColor: Color

    @State private var iconScale: CGFloat = 0.6
    @State private var iconOpacity: Double = 0.0
    @State private var textOpacity: Double = 0.0

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                // Glow ring
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                accentColor.opacity(0.2),
                                accentColor.opacity(0.05),
                                Color.clear,
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)

                Circle()
                    .stroke(accentColor.opacity(0.2), lineWidth: 1.5)
                    .frame(width: 120, height: 120)

                Image(systemName: icon)
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(accentColor)
                    .symbolRenderingMode(.hierarchical)
            }
            .scaleEffect(iconScale)
            .opacity(iconOpacity)

            VStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 40)
            }
            .opacity(textOpacity)

            Spacer()
            Spacer()
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.65).delay(0.1)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                textOpacity = 1.0
            }
        }
    }
}

// MARK: - Shimmer Button

private struct ShimmerGetStartedButton: View {
    let action: () -> Void

    @State private var shimmerOffset: CGFloat = -1.0

    var body: some View {
        Button(action: action) {
            Text("Get Started")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(hex: 0xFFB800),
                                        Color(hex: 0xFFC830),
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )

                        // Shimmer sweep
                        RoundedRectangle(cornerRadius: 18)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.0),
                                        .white.opacity(0.35),
                                        .white.opacity(0.0),
                                    ],
                                    startPoint: UnitPoint(x: shimmerOffset - 0.3, y: 0.5),
                                    endPoint: UnitPoint(x: shimmerOffset + 0.3, y: 0.5)
                                )
                            )
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: Color(hex: 0xFFB800).opacity(0.4), radius: 20, y: 8)
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: false)
                .delay(0.5)
            ) {
                shimmerOffset = 2.0
            }
        }
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @Environment(AppState.self) private var appState

    @State private var currentPage = 0
    @State private var taglineOpacity: Double = 0.0
    @State private var pagesVisible = false

    private let amber = Color(hex: 0xFFB800)

    private let pages: [(icon: String, title: String, subtitle: String, color: Color)] = [
        (
            "antenna.radiowaves.left.and.right",
            "Pair",
            "Find friends nearby with zero setup",
            Color(hex: 0x5E9EFF)
        ),
        (
            "hand.tap.fill",
            "Talk",
            "Press and hold. Just like a walkie-talkie.",
            Color(hex: 0xFFB800)
        ),
        (
            "lock.shield.fill",
            "Secure",
            "End-to-end encrypted.\nNo servers. No cloud.",
            Color(hex: 0x30D158)
        ),
    ]

    var body: some View {
        ZStack {
            // Deep dark background
            Color.black.ignoresSafeArea()

            // Animated mesh gradient
            MeshGradientBackground()

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 60)

                // Animated perch birds mascot
                PerchBirdsView(size: 240, isAnimating: true)
                    .frame(height: 160)
                    .padding(.bottom, 16)

                // Spring letter wordmark
                SpringWordmark()
                    .padding(.bottom, 6)

                // Tagline
                Text("Talk close. No towers needed.")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .opacity(taglineOpacity)

                Spacer()
                    .frame(height: 36)

                // Swipeable page view
                if pagesVisible {
                    TabView(selection: $currentPage) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                            OnboardingPage(
                                icon: page.icon,
                                title: page.title,
                                subtitle: page.subtitle,
                                accentColor: page.color
                            )
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 320)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))

                    // Custom amber page dots
                    HStack(spacing: 10) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            Capsule()
                                .fill(
                                    index == currentPage
                                        ? amber
                                        : amber.opacity(0.25)
                                )
                                .frame(
                                    width: index == currentPage ? 24 : 8,
                                    height: 8
                                )
                                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentPage)
                        }
                    }
                    .padding(.top, 4)
                }

                Spacer()

                // Get Started button (only on last page)
                if currentPage == pages.count - 1 {
                    ShimmerGetStartedButton {
                        appState.isOnboardingComplete = true
                    }
                    .padding(.horizontal, 32)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
                }

                // No internet badge
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 12, weight: .semibold))
                    Text("No internet required")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(amber.opacity(0.6))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(amber.opacity(0.08))
                        .overlay(
                            Capsule()
                                .stroke(amber.opacity(0.15), lineWidth: 0.5)
                        )
                )
                .padding(.top, 20)
                .opacity(taglineOpacity)

                Spacer()
                    .frame(height: 40)
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: currentPage)
        }
        .onAppear {
            startAnimations()
        }
    }

    // MARK: - Animations

    private func startAnimations() {
        // Tagline fades in after wordmark
        withAnimation(.easeOut(duration: 0.8).delay(0.9)) {
            taglineOpacity = 1.0
        }

        // Pages appear
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(1.3)) {
            pagesVisible = true
        }
    }
}
