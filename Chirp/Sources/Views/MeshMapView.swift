import SwiftUI

// MARK: - Mesh Node Model

private struct MeshNode: Identifiable {
    let id: String
    let name: String
    let isDirectPeer: Bool
    let isConnected: Bool
    let hopCount: Int
}

// MARK: - Pulse Model

private struct DataPulse: Identifiable {
    let id = UUID()
    let fromIndex: Int
    let toCenter: Bool
    var progress: Double = 0.0
}

// MARK: - Radar Grid Canvas

private struct RadarGridCanvas: View {
    let size: CGSize
    let nodeCount: Int
    let nodes: [MeshNode]
    let pulsePhase: Double

    private let amber = Constants.Colors.amber
    private let green = Constants.Colors.electricGreen

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let maxRadius = min(canvasSize.width, canvasSize.height) * 0.42

            // Subtle grid lines
            drawGrid(context: context, center: center, size: canvasSize)

            // Range rings at 80m intervals
            let ringDistances = [80, 160, 240]
            for (index, distance) in ringDistances.enumerated() {
                let radius = maxRadius * Double(index + 1) / 3.0
                let ringPath = Path(ellipseIn: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                context.stroke(
                    ringPath,
                    with: .color(amber.opacity(0.08 + Double(index) * 0.02)),
                    style: StrokeStyle(lineWidth: 0.5, dash: [4, 6])
                )

                // Range label
                let labelPoint = CGPoint(x: center.x + radius * 0.707 + 8, y: center.y - radius * 0.707 - 8)
                let text = Text("\(distance)m")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(amber.opacity(0.3))
                context.draw(context.resolve(text), at: labelPoint, anchor: .leading)
            }

            // Connection lines to direct peers
            let directNodes = nodes.filter { $0.isDirectPeer }
            let relayNodes = nodes.filter { !$0.isDirectPeer }

            let directRadius = maxRadius * 0.45
            let relayRadius = maxRadius * 0.80

            // Draw connection lines for direct peers
            for (index, _) in directNodes.enumerated() {
                let angle = peerAngle(index: index, total: directNodes.count)
                let peerPoint = CGPoint(
                    x: center.x + cos(angle) * directRadius,
                    y: center.y + sin(angle) * directRadius
                )

                // Solid amber line
                var linePath = Path()
                linePath.move(to: center)
                linePath.addLine(to: peerPoint)
                context.stroke(
                    linePath,
                    with: .color(amber.opacity(0.5)),
                    style: StrokeStyle(lineWidth: 1.5)
                )

                // Animated pulse dot traveling along the line
                let pulseT = (pulsePhase + Double(index) * 0.3).truncatingRemainder(dividingBy: 1.0)
                let pulsePoint = CGPoint(
                    x: center.x + (peerPoint.x - center.x) * pulseT,
                    y: center.y + (peerPoint.y - center.y) * pulseT
                )
                let pulseRect = CGRect(x: pulsePoint.x - 3, y: pulsePoint.y - 3, width: 6, height: 6)
                context.fill(Path(ellipseIn: pulseRect), with: .color(amber.opacity(0.8 * (1.0 - pulseT * 0.5))))

                // Hop count badge (1 hop)
                let midPoint = CGPoint(
                    x: (center.x + peerPoint.x) / 2,
                    y: (center.y + peerPoint.y) / 2
                )
                let hopText = Text("1")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(amber.opacity(0.6))
                context.draw(context.resolve(hopText), at: CGPoint(x: midPoint.x + 8, y: midPoint.y - 8))
            }

            // Draw connection lines for relay peers
            for (index, node) in relayNodes.enumerated() {
                let angle = peerAngle(index: index, total: relayNodes.count, offset: .pi / Double(max(relayNodes.count, 1)))
                let peerPoint = CGPoint(
                    x: center.x + cos(angle) * relayRadius,
                    y: center.y + sin(angle) * relayRadius
                )

                // Find nearest direct peer to draw relay chain through
                let nearestDirectIndex = directNodes.isEmpty ? 0 : index % directNodes.count
                let directAngle = peerAngle(index: nearestDirectIndex, total: max(directNodes.count, 1))
                let relayThroughPoint = CGPoint(
                    x: center.x + cos(directAngle) * directRadius,
                    y: center.y + sin(directAngle) * directRadius
                )

                // Dashed faded line from relay point to outer peer
                var dashedPath = Path()
                dashedPath.move(to: relayThroughPoint)
                dashedPath.addLine(to: peerPoint)
                context.stroke(
                    dashedPath,
                    with: .color(Color.gray.opacity(0.3)),
                    style: StrokeStyle(lineWidth: 1.0, dash: [4, 4])
                )

                // Pulse on dashed line
                let pulseT = (pulsePhase + Double(index) * 0.4 + 0.5).truncatingRemainder(dividingBy: 1.0)
                let dashPulse = CGPoint(
                    x: relayThroughPoint.x + (peerPoint.x - relayThroughPoint.x) * pulseT,
                    y: relayThroughPoint.y + (peerPoint.y - relayThroughPoint.y) * pulseT
                )
                let dashRect = CGRect(x: dashPulse.x - 2, y: dashPulse.y - 2, width: 4, height: 4)
                context.fill(Path(ellipseIn: dashRect), with: .color(Color.gray.opacity(0.5 * (1.0 - pulseT))))

                // Hop count badge
                let hopMid = CGPoint(
                    x: (relayThroughPoint.x + peerPoint.x) / 2 + 8,
                    y: (relayThroughPoint.y + peerPoint.y) / 2 - 8
                )
                let hopText = Text("\(node.hopCount)")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.gray.opacity(0.5))
                context.draw(context.resolve(hopText), at: hopMid)
            }

            // Center glow for your device
            let glowRadius: CGFloat = 40
            let glowRect = CGRect(
                x: center.x - glowRadius,
                y: center.y - glowRadius,
                width: glowRadius * 2,
                height: glowRadius * 2
            )
            context.fill(
                Path(ellipseIn: glowRect),
                with: .radialGradient(
                    Gradient(colors: [amber.opacity(0.25), amber.opacity(0.0)]),
                    center: center,
                    startRadius: 0,
                    endRadius: glowRadius
                )
            )
        }
    }

    private func drawGrid(context: GraphicsContext, center: CGPoint, size: CGSize) {
        let spacing: CGFloat = 40
        let cols = Int(size.width / spacing) + 1
        let rows = Int(size.height / spacing) + 1

        for col in 0...cols {
            let x = CGFloat(col) * spacing
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: .color(Color.white.opacity(0.02)), lineWidth: 0.5)
        }

        for row in 0...rows {
            let y = CGFloat(row) * spacing
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(Color.white.opacity(0.02)), lineWidth: 0.5)
        }

        // Cross-hair through center
        var hLine = Path()
        hLine.move(to: CGPoint(x: 0, y: center.y))
        hLine.addLine(to: CGPoint(x: size.width, y: center.y))
        context.stroke(hLine, with: .color(Color.white.opacity(0.04)), lineWidth: 0.5)

        var vLine = Path()
        vLine.move(to: CGPoint(x: center.x, y: 0))
        vLine.addLine(to: CGPoint(x: center.x, y: size.height))
        context.stroke(vLine, with: .color(Color.white.opacity(0.04)), lineWidth: 0.5)
    }

    private func peerAngle(index: Int, total: Int, offset: Double = 0) -> Double {
        guard total > 0 else { return 0 }
        return (2.0 * .pi * Double(index) / Double(total)) - .pi / 2.0 + offset
    }
}

// MARK: - Node Bubble View

private struct NodeBubble: View {
    let node: MeshNode
    let isCenter: Bool

    private let amber = Constants.Colors.amber
    private let green = Constants.Colors.electricGreen

    var body: some View {
        ZStack {
            if isCenter {
                // Outer glow ring
                Circle()
                    .fill(amber.opacity(0.15))
                    .frame(width: 56, height: 56)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [amber.opacity(0.3), amber.opacity(0.05)],
                            center: .center,
                            startRadius: 8,
                            endRadius: 28
                        )
                    )
                    .frame(width: 56, height: 56)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [amber, amber.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                    )
                    .shadow(color: amber.opacity(0.6), radius: 12)
            } else {
                let nodeColor = node.isDirectPeer ? green : Color.gray

                Circle()
                    .fill(nodeColor.opacity(0.15))
                    .frame(width: 40, height: 40)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [nodeColor.opacity(0.8), nodeColor.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(node.name.prefix(1)).uppercased())
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    )
                    .shadow(color: nodeColor.opacity(0.4), radius: 8)
            }
        }
    }
}

// MARK: - Mesh Map View

struct MeshMapView: View {
    @Environment(AppState.self) private var appState

    private let amber = Constants.Colors.amber
    private let green = Constants.Colors.electricGreen

    private var meshNodes: [MeshNode] {
        guard let channel = appState.channelManager.activeChannel else { return [] }
        return channel.peers.map { peer in
            MeshNode(
                id: peer.id,
                name: peer.name,
                isDirectPeer: true,
                isConnected: peer.isConnected,
                hopCount: 1
            )
        }
    }

    private var directNodes: [MeshNode] {
        meshNodes.filter { $0.isDirectPeer }
    }

    private var relayNodes: [MeshNode] {
        meshNodes.filter { !$0.isDirectPeer }
    }

    private var totalNodeCount: Int {
        meshNodes.count + 1 // +1 for self
    }

    private var maxHops: Int {
        meshNodes.map(\.hopCount).max() ?? 0
    }

    private var estimatedRange: Int {
        maxHops > 0 ? maxHops * 80 : (meshNodes.isEmpty ? 0 : 80)
    }

    var body: some View {
        ZStack {
            // Dark background
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                let size = geo.size
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxRadius = min(size.width, size.height) * 0.42
                let directRadius = maxRadius * 0.45
                let relayRadius = maxRadius * 0.80

                // Animated canvas layer
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.5) / 2.5

                    RadarGridCanvas(
                        size: size,
                        nodeCount: meshNodes.count,
                        nodes: meshNodes,
                        pulsePhase: phase
                    )
                }

                // Center node (you)
                NodeBubble(
                    node: MeshNode(id: "self", name: appState.callsign, isDirectPeer: true, isConnected: true, hopCount: 0),
                    isCenter: true
                )
                .position(center)

                // Your callsign label below center node
                Text("You")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(amber.opacity(0.7))
                    .position(x: center.x, y: center.y + 36)

                // Direct peer nodes
                ForEach(Array(directNodes.enumerated()), id: \.element.id) { index, node in
                    let angle = peerAngle(index: index, total: directNodes.count)
                    let point = CGPoint(
                        x: center.x + cos(angle) * directRadius,
                        y: center.y + sin(angle) * directRadius
                    )

                    VStack(spacing: 2) {
                        NodeBubble(node: node, isCenter: false)

                        Text(node.name.split(separator: " ").first.map(String.init) ?? node.name)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    .position(point)
                }

                // Relay nodes (further out)
                ForEach(Array(relayNodes.enumerated()), id: \.element.id) { index, node in
                    let angle = peerAngle(index: index, total: relayNodes.count, offset: .pi / Double(max(relayNodes.count, 1)))
                    let point = CGPoint(
                        x: center.x + cos(angle) * relayRadius,
                        y: center.y + sin(angle) * relayRadius
                    )

                    VStack(spacing: 2) {
                        NodeBubble(node: node, isCenter: false)

                        Text(node.name.split(separator: " ").first.map(String.init) ?? node.name)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                    .position(point)
                }

                // Empty state overlay
                if meshNodes.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()

                        scanningRipple
                            .frame(height: 120)

                        Text("Scanning for mesh peers...")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))

                        Text("Nearby ChirpChirp devices will appear here")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.25))

                        Spacer()
                            .frame(height: 100)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Stats bar at bottom
            VStack {
                Spacer()
                statsBar
            }
        }
        .navigationTitle("Mesh Network")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 20) {
            statItem(value: "\(totalNodeCount)", label: "nodes")
            statDivider
            statItem(value: "\(maxHops)", label: "hops max")
            statDivider
            statItem(value: "~\(estimatedRange)m", label: "range")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(amber.opacity(0.15), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private func statItem(value: String, label: String) -> some View {
        HStack(spacing: 6) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(amber)

            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var statDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.1))
            .frame(width: 1, height: 16)
    }

    // MARK: - Scanning Ripple

    private var scanningRipple: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)

                for ring in 0..<3 {
                    let phase = (t * 0.5 + Double(ring) * 0.33).truncatingRemainder(dividingBy: 1.0)
                    let radius = 15.0 + phase * 45.0
                    let opacity = (1.0 - phase) * 0.3

                    let path = Path(ellipseIn: CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    ))
                    context.stroke(path, with: .color(amber.opacity(opacity)), lineWidth: 1.5)
                }
            }
        }
    }

    // MARK: - Helpers

    private func peerAngle(index: Int, total: Int, offset: Double = 0) -> Double {
        guard total > 0 else { return 0 }
        return (2.0 * .pi * Double(index) / Double(total)) - .pi / 2.0 + offset
    }
}
