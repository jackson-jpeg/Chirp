import SwiftUI

// MARK: - Animated Mesh Gradient Background

private struct MeshGradientBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let w = size.width
                let h = size.height

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

// MARK: - Animated Network Nodes Background

private struct NetworkNodesBackground: View {
    @State private var nodePositions: [(x: CGFloat, y: CGFloat)] = []
    @State private var lineOpacities: [Double] = []
    @State private var phase: CGFloat = 0

    private let nodeCount = 12

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let w = size.width
                let h = size.height

                // Generate stable animated positions
                var positions: [(CGFloat, CGFloat)] = []
                for i in 0..<nodeCount {
                    let baseX = (CGFloat(i % 4) + 0.5) / 4.0
                    let baseY = (CGFloat(i / 4) + 0.5) / 3.0
                    let dx = sin(t * 0.3 + Double(i) * 1.7) * 0.06
                    let dy = cos(t * 0.25 + Double(i) * 2.1) * 0.05
                    positions.append(((baseX + dx) * w, (baseY + dy) * h))
                }

                // Draw connections between nearby nodes
                let connectDist = w * 0.35
                for i in 0..<positions.count {
                    for j in (i+1)..<positions.count {
                        let dx = positions[i].0 - positions[j].0
                        let dy = positions[i].1 - positions[j].1
                        let dist = sqrt(dx * dx + dy * dy)
                        if dist < connectDist {
                            let alpha = (1.0 - dist / connectDist) * 0.15
                            var path = Path()
                            path.move(to: CGPoint(x: positions[i].0, y: positions[i].1))
                            path.addLine(to: CGPoint(x: positions[j].0, y: positions[j].1))
                            context.stroke(path, with: .color(.white.opacity(alpha)), lineWidth: 0.8)
                        }
                    }
                }

                // Draw nodes
                for (i, pos) in positions.enumerated() {
                    let pulse = sin(t * 1.5 + Double(i) * 0.8) * 0.5 + 0.5
                    let nodeSize: CGFloat = 3 + pulse * 2
                    let glowSize: CGFloat = nodeSize * 4

                    // Glow
                    let glowRect = CGRect(
                        x: pos.0 - glowSize / 2,
                        y: pos.1 - glowSize / 2,
                        width: glowSize,
                        height: glowSize
                    )
                    context.fill(
                        Path(ellipseIn: glowRect),
                        with: .color(.white.opacity(0.04 + pulse * 0.03))
                    )

                    // Core
                    let rect = CGRect(
                        x: pos.0 - nodeSize / 2,
                        y: pos.1 - nodeSize / 2,
                        width: nodeSize,
                        height: nodeSize
                    )
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(.white.opacity(0.2 + pulse * 0.15))
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Typewriter Text

private struct TypewriterText: View {
    let fullText: String
    let fontSize: CGFloat
    @State private var displayedCount: Int = 0
    @State private var cursorVisible = true

    var body: some View {
        HStack(spacing: 0) {
            Text(String(fullText.prefix(displayedCount)))
                .font(.system(size: fontSize, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            // Cursor
            Rectangle()
                .fill(.white)
                .frame(width: 3, height: fontSize * 0.85)
                .opacity(cursorVisible ? 1 : 0)
                .padding(.leading, 2)
        }
        .onAppear {
            // Typewriter effect
            for i in 1...fullText.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) {
                    withAnimation(.easeOut(duration: 0.05)) {
                        displayedCount = i
                    }
                }
            }

            // Blinking cursor
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                cursorVisible.toggle()
            }
        }
    }
}

// MARK: - Tower Down Illustration (Scaled Up)

private struct TowerDownIllustration: View {
    @State private var towerOpacity: Double = 1.0
    @State private var slashOpacity: Double = 0.0
    @State private var phoneGlow: Double = 0.0
    @State private var signalPulse: CGFloat = 0

    var body: some View {
        let blue = Constants.Colors.blue500
        let red = Constants.Colors.hotRed

        GeometryReader { geo in
            let centerX = geo.size.width / 2
            let centerY = geo.size.height / 2

            ZStack {
                // Cell tower (fading out)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 72, weight: .medium))
                    .foregroundStyle(red.opacity(towerOpacity * 0.6))
                    .overlay(
                        Image(systemName: "xmark")
                            .font(.system(size: 52, weight: .bold))
                            .foregroundStyle(red)
                            .opacity(slashOpacity)
                    )
                    .position(x: centerX, y: centerY)

                // Phones lighting up around the dead tower
                ForEach(0..<6, id: \.self) { i in
                    let angle = Double(i) * 60.0 + 30.0
                    let rad = angle * .pi / 180
                    let dist: CGFloat = 110
                    ZStack {
                        // Signal rings
                        Circle()
                            .stroke(blue.opacity(0.2), lineWidth: 1)
                            .frame(width: 30 + signalPulse * 12, height: 30 + signalPulse * 12)
                            .opacity(Double(1.0 - signalPulse * 0.7))

                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(blue)
                    }
                    .opacity(phoneGlow)
                    .position(
                        x: centerX + cos(rad) * dist,
                        y: centerY + sin(rad) * dist
                    )
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0).delay(0.3)) {
                towerOpacity = 0.2
                slashOpacity = 1.0
            }
            withAnimation(.easeIn(duration: 0.8).delay(1.0)) {
                phoneGlow = 1.0
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(1.5)) {
                signalPulse = 1.0
            }
        }
    }
}

// MARK: - Animated Mesh Network Illustration (Scaled Up)

private struct MeshNetworkIllustration: View {
    @State private var nodeScales: [CGFloat] = Array(repeating: 0, count: 9)
    @State private var lineOpacities: [Double] = Array(repeating: 0, count: 12)
    @State private var pulsePhase: CGFloat = 0
    @State private var dataPacketProgress: CGFloat = 0

    private let nodes: [(x: CGFloat, y: CGFloat)] = [
        (0.5, 0.15),   // top center
        (0.2, 0.35),   // left upper
        (0.8, 0.35),   // right upper
        (0.1, 0.6),    // far left
        (0.35, 0.55),  // center left
        (0.65, 0.55),  // center right
        (0.9, 0.6),    // far right
        (0.3, 0.8),    // bottom left
        (0.7, 0.8),    // bottom right
    ]

    private let connections: [(Int, Int)] = [
        (0, 1), (0, 2), (1, 3), (1, 4), (2, 5), (2, 6),
        (3, 7), (4, 5), (4, 7), (5, 8), (6, 8), (7, 8)
    ]

    var body: some View {
        let blue = Constants.Colors.blue500

        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Connection lines
                ForEach(0..<connections.count, id: \.self) { i in
                    let from = nodes[connections[i].0]
                    let to = nodes[connections[i].1]
                    Path { path in
                        path.move(to: CGPoint(x: from.x * w, y: from.y * h))
                        path.addLine(to: CGPoint(x: to.x * w, y: to.y * h))
                    }
                    .stroke(blue.opacity(lineOpacities[i] * 0.35), lineWidth: 1.5)
                }

                // Data packet traveling along a path
                let pathFrom = nodes[0]
                let pathMid = nodes[4]
                let pathTo = nodes[7]
                Circle()
                    .fill(blue)
                    .frame(width: 6, height: 6)
                    .shadow(color: blue, radius: 6)
                    .position(
                        x: lerp(
                            from: lerp(from: pathFrom.x, to: pathMid.x, t: dataPacketProgress),
                            to: lerp(from: pathMid.x, to: pathTo.x, t: dataPacketProgress),
                            t: dataPacketProgress
                        ) * w,
                        y: lerp(
                            from: lerp(from: pathFrom.y, to: pathMid.y, t: dataPacketProgress),
                            to: lerp(from: pathMid.y, to: pathTo.y, t: dataPacketProgress),
                            t: dataPacketProgress
                        ) * h
                    )
                    .opacity(lineOpacities.first.map { $0 > 0 ? 1 : 0 } ?? 0)

                // Nodes
                ForEach(0..<nodes.count, id: \.self) { i in
                    let node = nodes[i]
                    ZStack {
                        // Glow
                        Circle()
                            .fill(blue.opacity(0.12))
                            .frame(width: 40, height: 40)

                        // Core
                        Circle()
                            .fill(blue)
                            .frame(width: 14, height: 14)

                        // Pulse ring
                        Circle()
                            .stroke(blue.opacity(0.25), lineWidth: 1)
                            .frame(width: 14 + pulsePhase * 24, height: 14 + pulsePhase * 24)
                            .opacity(1 - pulsePhase)

                        // Phone icon inside
                        Image(systemName: "iphone")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .scaleEffect(nodeScales[i])
                    .position(x: node.x * w, y: node.y * h)
                }
            }
        }
        .onAppear {
            for i in 0..<nodes.count {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(Double(i) * 0.08)) {
                    nodeScales[i] = 1.0
                }
            }
            for i in 0..<connections.count {
                withAnimation(.easeOut(duration: 0.5).delay(0.2 + Double(i) * 0.06)) {
                    lineOpacities[i] = 1.0
                }
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(1.0)) {
                pulsePhase = 1.0
            }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: false).delay(1.2)) {
                dataPacketProgress = 1.0
            }
        }
    }

    private func lerp(from: CGFloat, to: CGFloat, t: CGFloat) -> CGFloat {
        from + (to - from) * t
    }
}

// MARK: - Lock Shield Illustration (Scaled Up)

private struct EncryptionIllustration: View {
    @State private var shieldScale: CGFloat = 0.5
    @State private var lockOpacity: Double = 0.0
    @State private var ringRotation: Double = 0
    @State private var layerOpacities: [Double] = [0, 0, 0, 0]

    private let layerLabels = ["WiFi", "TLS", "AES-256", "Stego"]

    var body: some View {
        let green = Constants.Colors.electricGreen

        GeometryReader { geo in
            let centerX = geo.size.width / 2
            let centerY = geo.size.height * 0.45

            ZStack {
                // Concentric rings for 4 layers
                ForEach(0..<4, id: \.self) { i in
                    let size: CGFloat = CGFloat(180 + i * 40)
                    Circle()
                        .stroke(
                            green.opacity(0.08 + Double(3 - i) * 0.05),
                            lineWidth: 1.5
                        )
                        .frame(width: size, height: size)
                        .opacity(layerOpacities[i])
                        .position(x: centerX, y: centerY)
                }

                // Rotating outer ring
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [green.opacity(0.4), green.opacity(0.05), green.opacity(0.4)],
                            center: .center
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(ringRotation))
                    .position(x: centerX, y: centerY)

                // Inner glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [green.opacity(0.15), .clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                    .position(x: centerX, y: centerY)

                // Shield with lock
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 72, weight: .medium))
                    .foregroundStyle(green)
                    .symbolRenderingMode(.hierarchical)
                    .scaleEffect(shieldScale)
                    .opacity(lockOpacity)
                    .position(x: centerX, y: centerY)

                // Layer labels around the shield
                ForEach(0..<4, id: \.self) { i in
                    let angle = Double(i) * 90.0 - 45.0
                    let rad = angle * .pi / 180
                    let dist: CGFloat = 130
                    Text(layerLabels[i])
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(green.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(green.opacity(0.08))
                        )
                        .opacity(layerOpacities[i])
                        .position(
                            x: centerX + cos(rad) * dist,
                            y: centerY + sin(rad) * dist
                        )
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.6).delay(0.2)) {
                shieldScale = 1.0
                lockOpacity = 1.0
            }
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
            for i in 0..<4 {
                withAnimation(.easeOut(duration: 0.5).delay(0.5 + Double(i) * 0.15)) {
                    layerOpacities[i] = 1.0
                }
            }
        }
    }
}

// MARK: - Use Cases Illustration (Redesigned)

private struct UseCasesIllustration: View {
    @State private var visibleCount = 0

    private let useCases: [(icon: String, label: String)] = [
        ("waveform", "Push-to-Talk"),
        ("bubble.left.and.bubble.right.fill", "Messaging"),
        ("photo.fill", "Photo Sharing"),
        ("location.fill", "GPS Drops"),
        ("sos", "SOS Beacons"),
        ("lock.shield.fill", "Encrypted"),
    ]

    var body: some View {
        let blue = Constants.Colors.blue500

        GeometryReader { geo in
            let columns = 3
            let spacing: CGFloat = 16
            let hPadding: CGFloat = 24
            let available = geo.size.width - hPadding * 2 - spacing * CGFloat(columns - 1)
            let itemWidth = available / CGFloat(columns)

            let items = useCases.enumerated().map { ($0.offset, $0.element) }

            VStack(spacing: 20) {
                Spacer()
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<3, id: \.self) { col in
                            let idx = row * 3 + col
                            let item = items[idx]
                            VStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(blue.opacity(0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(blue.opacity(0.15), lineWidth: 1)
                                        )
                                        .frame(width: itemWidth, height: itemWidth * 0.85)

                                    Image(systemName: item.1.icon)
                                        .font(.system(size: 28, weight: .medium))
                                        .foregroundStyle(blue)
                                }
                                Text(item.1.label)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .scaleEffect(idx < visibleCount ? 1.0 : 0.5)
                            .opacity(idx < visibleCount ? 1.0 : 0.0)
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, hPadding)
        }
        .onAppear {
            for i in 0..<useCases.count {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(Double(i) * 0.1)) {
                    visibleCount = i + 1
                }
            }
        }
    }
}

// MARK: - Shimmer Get Started Button (Blue)

private struct ShimmerGetStartedButton: View {
    let action: () -> Void
    @State private var shimmerOffset: CGFloat = -1.0

    var body: some View {
        Button(action: action) {
            Text("Get Started")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Constants.Colors.blue600,
                                        Constants.Colors.blue500,
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )

                        RoundedRectangle(cornerRadius: 18)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.0),
                                        .white.opacity(0.25),
                                        .white.opacity(0.0),
                                    ],
                                    startPoint: UnitPoint(x: shimmerOffset - 0.3, y: 0.5),
                                    endPoint: UnitPoint(x: shimmerOffset + 0.3, y: 0.5)
                                )
                            )
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: Constants.Colors.blue500.opacity(0.4), radius: 20, y: 8)
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
        .accessibilityLabel("Get Started")
        .accessibilityIdentifier(AccessibilityID.getStartedButton)
    }
}

// MARK: - Next Button

private struct NextArrowButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("Next")
                    .font(.system(size: 17, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .frame(height: 50)
            .background(
                Capsule()
                    .fill(.white.opacity(0.12))
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }
}

// MARK: - Page Indicator Dots

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(
                        index == current
                            ? Color.white
                            : Color.white.opacity(0.25)
                    )
                    .frame(
                        width: index == current ? 24 : 8,
                        height: 8
                    )
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: current)
            }
        }
    }
}

// MARK: - Onboarding Page Content

private struct OnboardingPageContent: View {
    let title: String
    let subtitle: String
    let illustration: AnyView
    let showIllustrationAbove: Bool

    @State private var textOpacity: Double = 0.0
    @State private var textOffset: CGFloat = 20.0

    init(title: String, subtitle: String, illustration: AnyView, showIllustrationAbove: Bool = true) {
        self.title = title
        self.subtitle = subtitle
        self.illustration = illustration
        self.showIllustrationAbove = showIllustrationAbove
    }

    var body: some View {
        VStack(spacing: 0) {
            if showIllustrationAbove {
                // Illustration fills upper portion
                illustration
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .padding(.top, 20)

                Spacer().frame(height: 32)
            }

            // Title
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
                .opacity(textOpacity)
                .offset(y: textOffset)

            Spacer().frame(height: 14)

            // Subtitle
            Text(subtitle)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)
                .opacity(textOpacity)
                .offset(y: textOffset)

            if !showIllustrationAbove {
                Spacer().frame(height: 32)
                illustration
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
            }

            Spacer(minLength: 20)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.15)) {
                textOpacity = 1.0
                textOffset = 0.0
            }
        }
    }
}

// MARK: - Hero Page (Page 1)

private struct HeroPage: View {
    @State private var wordmarkOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0
    @State private var subtitleOffset: CGFloat = 15

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Small wordmark at top
            Text("ChirpChirp")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .opacity(wordmarkOpacity)
                .padding(.bottom, 60)

            // Big typewriter text
            TypewriterText(fullText: "Your phone is the network.", fontSize: 36)
                .padding(.horizontal, 32)

            Spacer().frame(height: 40)

            // Subtle tagline
            Text("No towers. No subscriptions. Just people.")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
                .opacity(subtitleOpacity)
                .offset(y: subtitleOffset)

            Spacer()
            Spacer()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                wordmarkOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.7).delay(2.0)) {
                subtitleOpacity = 1.0
                subtitleOffset = 0
            }
        }
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @Environment(AppState.self) private var appState

    @State private var currentPage = 0
    private let totalPages = 5

    var body: some View {
        ZStack {
            // Background layers
            Color.black.ignoresSafeArea()
            MeshGradientBackground()
            if currentPage == 0 {
                NetworkNodesBackground()
                    .opacity(0.6)
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                // Skip button (pages 0-3)
                HStack {
                    Spacer()
                    if currentPage < totalPages - 1 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentPage = totalPages - 1
                            }
                        } label: {
                            Text("Skip")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .transition(.opacity)
                    }
                }
                .frame(height: 44)
                .padding(.horizontal, 8)

                // Full-screen page content
                TabView(selection: $currentPage) {
                    // Page 1: Hero
                    HeroPage()
                        .tag(0)

                    // Page 2: No Towers
                    OnboardingPageContent(
                        title: "No towers. No Wi-Fi. No problem.",
                        subtitle: "ChirpChirp uses Bluetooth and Wi-Fi Direct to connect phones directly. Works in basements, blackouts, and the backcountry.",
                        illustration: AnyView(TowerDownIllustration())
                    )
                    .tag(1)

                    // Page 3: Mesh
                    OnboardingPageContent(
                        title: "Every phone extends the network",
                        subtitle: "Your messages hop from phone to phone. 5 people can cover a kilometer with zero infrastructure.",
                        illustration: AnyView(MeshNetworkIllustration())
                    )
                    .tag(2)

                    // Page 4: Use Cases
                    OnboardingPageContent(
                        title: "Talk. Text. Share. Survive.",
                        subtitle: "Push-to-talk, encrypted messaging, photo sharing, GPS drops, SOS beacons — all without a single bar of signal.",
                        illustration: AnyView(UseCasesIllustration())
                    )
                    .tag(3)

                    // Page 5: Encryption
                    OnboardingPageContent(
                        title: "Military-grade encryption. Four layers deep.",
                        subtitle: "WiFi encryption, TLS transport, AES-256 channels, and steganographic encoding. Nobody can listen in.",
                        illustration: AnyView(EncryptionIllustration())
                    )
                    .tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Bottom controls
                VStack(spacing: 20) {
                    // Page dots
                    PageDots(count: totalPages, current: currentPage)

                    // Action button
                    if currentPage == totalPages - 1 {
                        ShimmerGetStartedButton {
                            appState.isOnboardingComplete = true
                        }
                        .padding(.horizontal, 32)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                    } else {
                        NextArrowButton {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentPage += 1
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .padding(.bottom, 40)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: currentPage)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
