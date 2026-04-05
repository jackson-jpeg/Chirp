import CoreLocation
import SwiftUI

// MARK: - Mesh Topology Node

private struct TopologyNode: Identifiable, Equatable {
    let id: String
    let name: String
    let hopCount: Int
    let isConnected: Bool
    let batteryLevel: Float
    let signalQuality: Double
    let lastSeen: Date
    let neighborIDs: [String]

    var isDirect: Bool { hopCount <= 1 }

    static func == (lhs: TopologyNode, rhs: TopologyNode) -> Bool {
        lhs.id == rhs.id
            && lhs.hopCount == rhs.hopCount
            && lhs.isConnected == rhs.isConnected
    }
}

// MARK: - Node Detail Sheet

private struct NodeDetailSheet: View {
    let node: TopologyNode
    @Environment(\.dismiss) private var dismiss

    private let amber = Constants.Colors.amber
    private let green = Constants.Colors.electricGreen

    var body: some View {
        VStack(spacing: Constants.Layout.horizontalPadding) {
            // Drag indicator
            Capsule()
                .fill(Constants.Colors.textTertiary)
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            // Node avatar
            ZStack {
                Circle()
                    .fill(nodeColor.opacity(0.2))
                    .frame(width: 64, height: 64)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [nodeColor.opacity(0.9), nodeColor.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .overlay(
                        Text(String(node.name.prefix(1)).uppercased())
                            .font(Constants.Typography.sectionTitle)
                            .foregroundStyle(Constants.Colors.textPrimary)
                    )
                    .shadow(color: nodeColor.opacity(0.5), radius: 10)
            }

            Text(node.name)
                .font(Constants.Typography.sectionTitle)
                .foregroundStyle(Constants.Colors.textPrimary)

            // Detail rows
            VStack(spacing: Constants.Layout.glassCornerRadius) {
                detailRow(icon: "arrow.triangle.branch", label: "Hop Count", value: "\(node.hopCount)")
                detailRow(icon: "battery.75percent", label: "Battery", value: batteryString)
                detailRow(icon: "wifi", label: "Signal Quality", value: qualityString)
                detailRow(icon: "clock", label: "Last Seen", value: lastSeenString)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, Constants.Layout.spacing)
            .background(
                RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius)
                    .fill(Constants.Colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius)
                            .fill(Constants.Colors.surfaceGlass)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius)
                            .stroke(Constants.Colors.surfaceBorder, lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, Constants.Layout.horizontalPadding)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Constants.Colors.backgroundTertiary, Constants.Colors.slate900],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private var nodeColor: Color {
        if node.signalQuality > 0.7 { return green }
        if node.signalQuality > 0.3 { return amber }
        return Constants.Colors.hotRed
    }

    private var batteryString: String {
        if node.batteryLevel < 0 { return "Unknown" }
        return "\(Int(node.batteryLevel * 100))%"
    }

    private var qualityString: String {
        let pct = Int(node.signalQuality * 100)
        if node.signalQuality > 0.7 { return "\(pct)% — Good" }
        if node.signalQuality > 0.3 { return "\(pct)% — Fair" }
        return "\(pct)% — Poor"
    }

    private var lastSeenString: String {
        let interval = Date().timeIntervalSince(node.lastSeen)
        if interval < 2 { return "Just now" }
        if interval < 60 { return "\(Int(interval))s ago" }
        return "\(Int(interval / 60))m ago"
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(Constants.Typography.caption)
                .foregroundStyle(amber.opacity(0.7))
                .frame(width: 24)
            Text(label)
                .font(Constants.Typography.caption)
                .foregroundStyle(Constants.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(Constants.Typography.monoStatus)
                .foregroundStyle(Constants.Colors.textPrimary.opacity(0.9))
        }
    }
}

// MARK: - Topology Canvas

private struct TopologyCanvas: View {
    let size: CGSize
    let nodes: [TopologyNode]
    let pulsePhase: Double
    let meshHealthScore: Double
    let sosActive: Bool
    let hopPath: HopPath?
    let selfID: String

    private let amber = Constants.Colors.amber
    private let green = Constants.Colors.electricGreen
    private let red = Constants.Colors.hotRed

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let maxRadius = min(canvasSize.width, canvasSize.height) * 0.40

            // 1. Subtle background grid
            drawGrid(context: context, center: center, size: canvasSize)

            // 2. Range rings with labels
            drawRangeRings(context: context, center: center, maxRadius: maxRadius)

            // 3. Connection lines with quality colors and pulse dots
            drawConnections(context: context, center: center, maxRadius: maxRadius)

            // 4. Self node glow
            drawSelfGlow(context: context, center: center)

            // 5. Hop path overlay
            if let hopPath {
                drawHopPath(context: context, center: center, maxRadius: maxRadius, hopPath: hopPath)
            }

            // 6. SOS border pulse
            if sosActive {
                drawSOSBorder(context: context, size: canvasSize)
            }
        }
    }

    // MARK: - Grid

    private func drawGrid(context: GraphicsContext, center: CGPoint, size: CGSize) {
        let spacing: CGFloat = 40
        let cols = Int(size.width / spacing) + 1
        let rows = Int(size.height / spacing) + 1

        for col in 0...cols {
            let x = CGFloat(col) * spacing
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: .color(Constants.Colors.surfaceBorder.opacity(0.2)), lineWidth: 0.5)
        }

        for row in 0...rows {
            let y = CGFloat(row) * spacing
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(Constants.Colors.surfaceBorder.opacity(0.2)), lineWidth: 0.5)
        }

        // Crosshair
        var hLine = Path()
        hLine.move(to: CGPoint(x: 0, y: center.y))
        hLine.addLine(to: CGPoint(x: size.width, y: center.y))
        context.stroke(hLine, with: .color(Constants.Colors.surfaceBorder.opacity(0.4)), lineWidth: 0.5)

        var vLine = Path()
        vLine.move(to: CGPoint(x: center.x, y: 0))
        vLine.addLine(to: CGPoint(x: center.x, y: size.height))
        context.stroke(vLine, with: .color(Constants.Colors.surfaceBorder.opacity(0.4)), lineWidth: 0.5)
    }

    // MARK: - Range Rings

    private func drawRangeRings(context: GraphicsContext, center: CGPoint, maxRadius: CGFloat) {
        let maxHop = max(3, (nodes.map(\.hopCount).max() ?? 1) + 1)
        let ringCount = min(maxHop, 5)

        for hop in 1...ringCount {
            let radius = maxRadius * CGFloat(hop) / CGFloat(ringCount)
            let ringPath = Path(ellipseIn: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            let opacity = 0.06 + Double(hop) * 0.015
            context.stroke(
                ringPath,
                with: .color(amber.opacity(opacity)),
                style: StrokeStyle(lineWidth: 0.5, dash: [4, 6])
            )

            // Range label
            let distance = hop * 80
            let labelAngle: Double = -.pi / 4.0  // 45 degrees up-right
            let labelPoint = CGPoint(
                x: center.x + radius * CGFloat(cos(labelAngle)) + 10,
                y: center.y + radius * CGFloat(sin(labelAngle)) - 10
            )
            let text = Text("\(distance)m")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(amber.opacity(0.25))
            context.draw(context.resolve(text), at: labelPoint, anchor: .leading)
        }
    }

    // MARK: - Connection Lines

    private func drawConnections(context: GraphicsContext, center: CGPoint, maxRadius: CGFloat) {
        let maxHop = max(3, (nodes.map(\.hopCount).max() ?? 1) + 1)

        // Group nodes by hop count for ring layout
        let hopGroups = Dictionary(grouping: nodes) { $0.hopCount }

        // Draw connections: direct nodes connect to center, relay nodes connect to nearest inner-ring node
        for node in nodes {
            let nodePoint = positionForNode(node, center: center, maxRadius: maxRadius, maxHop: maxHop, allNodes: nodes)

            if node.hopCount <= 1 {
                // Direct peer: line to center
                drawLink(
                    context: context,
                    from: center,
                    to: nodePoint,
                    quality: node.signalQuality,
                    pulseOffset: Double(abs(node.id.hashValue % 100)) / 100.0
                )
            } else {
                // Relay peer: connect to the nearest node in the previous hop ring
                let innerHop = node.hopCount - 1
                if let innerNodes = hopGroups[Int(innerHop)], !innerNodes.isEmpty {
                    // Find nearest inner node (by angle proximity or neighbor relationship)
                    let bestInner = innerNodes.min { a, b in
                        let posA = positionForNode(a, center: center, maxRadius: maxRadius, maxHop: maxHop, allNodes: nodes)
                        let posB = positionForNode(b, center: center, maxRadius: maxRadius, maxHop: maxHop, allNodes: nodes)
                        let dA = hypot(posA.x - nodePoint.x, posA.y - nodePoint.y)
                        let dB = hypot(posB.x - nodePoint.x, posB.y - nodePoint.y)
                        return dA < dB
                    }
                    if let inner = bestInner {
                        let innerPoint = positionForNode(inner, center: center, maxRadius: maxRadius, maxHop: maxHop, allNodes: nodes)
                        drawLink(
                            context: context,
                            from: innerPoint,
                            to: nodePoint,
                            quality: node.signalQuality,
                            pulseOffset: Double(abs(node.id.hashValue % 100)) / 100.0,
                            dashed: true
                        )
                    }
                } else {
                    // Fallback: connect to center
                    drawLink(
                        context: context,
                        from: center,
                        to: nodePoint,
                        quality: node.signalQuality,
                        pulseOffset: Double(abs(node.id.hashValue % 100)) / 100.0,
                        dashed: true
                    )
                }
            }
        }
    }

    private func drawLink(
        context: GraphicsContext,
        from: CGPoint,
        to: CGPoint,
        quality: Double,
        pulseOffset: Double,
        dashed: Bool = false
    ) {
        let lineColor = colorForQuality(quality)

        var linePath = Path()
        linePath.move(to: from)
        linePath.addLine(to: to)

        let style = dashed
            ? StrokeStyle(lineWidth: 1.0, dash: [4, 4])
            : StrokeStyle(lineWidth: 1.5)

        context.stroke(
            linePath,
            with: .color(lineColor.opacity(dashed ? 0.35 : 0.5)),
            style: style
        )

        // Animated pulse dot traveling along the line
        let t = (pulsePhase + pulseOffset).truncatingRemainder(dividingBy: 1.0)
        let pulsePoint = CGPoint(
            x: from.x + (to.x - from.x) * t,
            y: from.y + (to.y - from.y) * t
        )
        let dotSize: CGFloat = dashed ? 4 : 5
        let pulseRect = CGRect(
            x: pulsePoint.x - dotSize / 2,
            y: pulsePoint.y - dotSize / 2,
            width: dotSize,
            height: dotSize
        )
        context.fill(
            Path(ellipseIn: pulseRect),
            with: .color(amber.opacity(0.85 * (1.0 - t * 0.4)))
        )
    }

    private func colorForQuality(_ quality: Double) -> Color {
        if quality > 0.7 { return Constants.Colors.meshHealthGood }
        if quality > 0.3 { return Constants.Colors.meshHealthFair }
        return Constants.Colors.meshHealthPoor
    }

    // MARK: - Self Glow

    private func drawSelfGlow(context: GraphicsContext, center: CGPoint) {
        let glowRadius: CGFloat = 44
        let glowRect = CGRect(
            x: center.x - glowRadius,
            y: center.y - glowRadius,
            width: glowRadius * 2,
            height: glowRadius * 2
        )
        context.fill(
            Path(ellipseIn: glowRect),
            with: .radialGradient(
                Gradient(colors: [amber.opacity(0.3), amber.opacity(0.0)]),
                center: center,
                startRadius: 0,
                endRadius: glowRadius
            )
        )
    }

    // MARK: - Hop Path Overlay

    private func drawHopPath(
        context: GraphicsContext,
        center: CGPoint,
        maxRadius: CGFloat,
        hopPath: HopPath
    ) {
        let maxHop = max(3, (nodes.map(\.hopCount).max() ?? 1) + 1)

        for link in hopPath.links {
            // Resolve start point: "self" -> center, otherwise find node position
            let fromPoint: CGPoint
            if link.fromID == selfID {
                fromPoint = center
            } else if let node = nodes.first(where: { $0.id == link.fromID }) {
                fromPoint = positionForNode(node, center: center, maxRadius: maxRadius, maxHop: maxHop, allNodes: nodes)
            } else {
                continue
            }

            // Resolve end point
            guard let toNode = nodes.first(where: { $0.id == link.toID }) else { continue }
            let toPoint = positionForNode(toNode, center: center, maxRadius: maxRadius, maxHop: maxHop, allNodes: nodes)

            // Color by quality: green > 0.7, yellow 0.4-0.7, red < 0.4
            let linkColor: Color
            if link.quality > 0.7 {
                linkColor = Constants.Colors.meshHealthGood
            } else if link.quality >= 0.4 {
                linkColor = Constants.Colors.meshHealthFair
            } else {
                linkColor = Constants.Colors.meshHealthPoor
            }

            // Draw thick glowing path segment
            var path = Path()
            path.move(to: fromPoint)
            path.addLine(to: toPoint)

            // Outer glow
            context.stroke(path, with: .color(linkColor.opacity(0.25)), style: StrokeStyle(lineWidth: 8, lineCap: .round))
            // Main stroke
            context.stroke(path, with: .color(linkColor.opacity(0.9)), style: StrokeStyle(lineWidth: 3, lineCap: .round))

            // Animated pulse traveling along the path segment
            let t = pulsePhase
            let pulsePoint = CGPoint(
                x: fromPoint.x + (toPoint.x - fromPoint.x) * t,
                y: fromPoint.y + (toPoint.y - fromPoint.y) * t
            )
            let pulseRect = CGRect(x: pulsePoint.x - 5, y: pulsePoint.y - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: pulseRect), with: .color(.white.opacity(0.9)))
        }

        // Draw hop count badge at the midpoint of the path
        if let lastLink = hopPath.links.last,
           let toNode = nodes.first(where: { $0.id == lastLink.toID }) {
            let toPoint = positionForNode(toNode, center: center, maxRadius: maxRadius, maxHop: maxHop, allNodes: nodes)
            // Badge position: offset above the destination node
            let badgeCenter = CGPoint(x: toPoint.x + 18, y: toPoint.y - 18)
            let badgeSize: CGFloat = 22
            let badgeRect = CGRect(
                x: badgeCenter.x - badgeSize / 2,
                y: badgeCenter.y - badgeSize / 2,
                width: badgeSize,
                height: badgeSize
            )
            context.fill(Path(ellipseIn: badgeRect), with: .color(amber))
            let hopText = Text("\(hopPath.hopCount)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
            context.draw(context.resolve(hopText), at: badgeCenter, anchor: .center)
        }
    }

    // MARK: - SOS Border

    private func drawSOSBorder(context: GraphicsContext, size: CGSize) {
        let borderOpacity = 0.3 + 0.4 * abs(sin(pulsePhase * .pi * 2))
        let borderRect = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
        let borderPath = Path(roundedRect: borderRect, cornerRadius: 0)
        context.stroke(
            borderPath,
            with: .color(Constants.Colors.emergencyRed.opacity(borderOpacity)),
            style: StrokeStyle(lineWidth: 4)
        )
    }

    // MARK: - Node Positioning (delegate to shared function)

    func positionForNode(
        _ node: TopologyNode,
        center: CGPoint,
        maxRadius: CGFloat,
        maxHop: Int,
        allNodes: [TopologyNode]
    ) -> CGPoint {
        nodePosition(for: node, center: center, maxRadius: maxRadius, maxHop: maxHop, allNodes: allNodes)
    }
}

// MARK: - Node Bubble View

private struct NodeBubble: View {
    let node: TopologyNode
    let isCenter: Bool

    private let amber = Constants.Colors.amber
    private let green = Constants.Colors.electricGreen

    var body: some View {
        ZStack {
            if isCenter {
                // Outer glow ring
                Circle()
                    .fill(amber.opacity(0.15))
                    .frame(width: 58, height: 58)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [amber.opacity(0.3), amber.opacity(0.05)],
                            center: .center,
                            startRadius: 8,
                            endRadius: 29
                        )
                    )
                    .frame(width: 58, height: 58)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [amber, amber.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.black)
                    )
                    .shadow(color: amber.opacity(0.6), radius: 14)
            } else {
                let nodeColor = qualityColor

                Circle()
                    .fill(nodeColor.opacity(0.15))
                    .frame(width: 38, height: 38)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [nodeColor.opacity(0.8), nodeColor.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 30)
                    .overlay(
                        Text(String(node.name.prefix(1)).uppercased())
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    )
                    .shadow(color: nodeColor.opacity(0.4), radius: 8)
            }
        }
    }

    private var qualityColor: Color {
        if node.signalQuality > 0.7 { return green }
        if node.signalQuality > 0.3 { return amber }
        return Constants.Colors.hotRed
    }
}

// MARK: - Health Score View

private struct HealthScoreView: View {
    let score: Double

    private let amber = Constants.Colors.amber
    private let green = Constants.Colors.electricGreen
    private let red = Constants.Colors.hotRed

    var body: some View {
        VStack(spacing: 2) {
            Text("\(Int(score * 100))")
                .font(Constants.Typography.headline)
                .foregroundStyle(scoreColor)
                .contentTransition(.numericText())

            Text("MESH HEALTH")
                .font(Constants.Typography.badge)
                .foregroundStyle(scoreColor.opacity(0.6))
                .tracking(1.5)
        }
    }

    private var scoreColor: Color {
        if score > 0.7 { return green }
        if score > 0.3 { return amber }
        return red
    }
}

// MARK: - Live Stats Bar

private struct LiveStatsBar: View {
    let stats: MeshStats?
    let maxHops: Int

    private let amber = Constants.Colors.amber

    var body: some View {
        HStack(spacing: 0) {
            statCounter(label: "RELAYED", value: stats.map { "\($0.relayed)" } ?? "0")
            divider
            statCounter(label: "DELIVERED", value: stats.map { "\($0.delivered)" } ?? "0")
            divider
            statCounter(label: "DEDUPED", value: stats.map { "\($0.deduplicated)" } ?? "0")
            divider
            statCounter(label: "MAX HOPS", value: "\(maxHops)")
        }
        .padding(.horizontal, Constants.Layout.spacing)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius)
                .fill(Constants.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius)
                        .fill(Constants.Colors.surfaceGlass)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius)
                        .stroke(Constants.Colors.surfaceBorder, lineWidth: 0.5)
                )
        )
        .padding(.horizontal, Constants.Layout.spacing)
        .padding(.bottom, 12)
    }

    private func statCounter(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(Constants.Typography.monoStatus)
                .foregroundStyle(amber)
                .contentTransition(.numericText())
            Text(label)
                .font(Constants.Typography.badge)
                .foregroundStyle(Constants.Colors.textTertiary)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Constants.Colors.surfaceBorder)
            .frame(width: 1, height: 28)
    }
}

// MARK: - SOS Badge

private struct SOSBadge: View {
    let pulsePhase: Double

    var body: some View {
        let opacity = 0.7 + 0.3 * abs(sin(pulsePhase * .pi * 3))

        Text("SOS ACTIVE")
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Constants.Colors.emergencyRed.opacity(opacity))
            )
            .overlay(
                Capsule()
                    .stroke(Constants.Colors.emergencyRed, lineWidth: 1)
            )
    }
}

// MARK: - Node Positioning (shared)

/// Compute the screen position for a topology node arranged in concentric hop rings.
private func nodePosition(
    for node: TopologyNode,
    center: CGPoint,
    maxRadius: CGFloat,
    maxHop: Int,
    allNodes: [TopologyNode]
) -> CGPoint {
    let hop = node.hopCount
    let radius = maxRadius * CGFloat(hop) / CGFloat(max(maxHop, 1))

    let sameHopNodes = allNodes.filter { $0.hopCount == hop }.sorted { $0.id < $1.id }
    let index = sameHopNodes.firstIndex(where: { $0.id == node.id }) ?? 0
    let total = sameHopNodes.count

    guard total > 0 else { return center }
    let hopOffset = Double(hop) * 0.3
    let angle = (2.0 * .pi * Double(index) / Double(total)) - .pi / 2.0 + hopOffset

    return CGPoint(
        x: center.x + cos(angle) * radius,
        y: center.y + sin(angle) * radius
    )
}

// MARK: - Mesh Map View

private enum MapTab: String, CaseIterable {
    case topology = "Topology"
    case map = "Map"
}

// MARK: - Hop Path Data

/// Represents a computed multi-hop path from self to a destination peer,
/// with per-link quality for color coding.
private struct HopPath: Equatable {
    struct Link: Equatable {
        let fromID: String
        let toID: String
        let quality: Double  // 0-1
    }
    let peerIDs: [String]  // ordered hop list (first hop -> destination)
    let links: [Link]
    let destinationName: String

    var hopCount: Int { peerIDs.count }
}

struct MeshMapView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedNode: TopologyNode?
    @State private var cachedHealthScore: Double = 0
    @State private var selectedTab: MapTab = .topology
    @State private var showOfflineMapSheet: Bool = false
    @State private var activeHopPath: HopPath?

    @Namespace private var meshUnderline
    private let amber = Constants.Colors.amber
    private let green = Constants.Colors.electricGreen

    // MARK: - Data

    /// Build topology nodes from MeshBeacon's sortedNodes if available,
    /// otherwise fall back to channel peers.
    private var topologyNodes: [TopologyNode] {
        // Use full mesh beacon topology — richer data than channel peers alone.
        let beaconNodes = appState.meshBeacon.sortedNodes
        guard !beaconNodes.isEmpty else {
            // Fall back to channel peers if no beacon data yet
            let peers = appState.channelManager.activeChannel?.peers ?? []
            return peers.map { peer in
                TopologyNode(
                    id: peer.id,
                    name: peer.name,
                    hopCount: 1,
                    isConnected: peer.isConnected,
                    batteryLevel: -1,
                    signalQuality: peer.transportType == .wifiAware || peer.transportType == .both ? 0.95 : 0.7,
                    lastSeen: Date(),
                    neighborIDs: []
                )
            }
        }

        return beaconNodes.map { beacon in
            let isStale = Date().timeIntervalSince(beacon.lastSeen) > 10
            return TopologyNode(
                id: beacon.id,
                name: beacon.name,
                hopCount: Int(beacon.hopCount),
                isConnected: !isStale,
                batteryLevel: beacon.batteryLevel,
                signalQuality: beacon.isDirect ? 0.9 : 0.5,
                lastSeen: beacon.lastSeen,
                neighborIDs: beacon.neighborIDs
            )
        }
    }

    private var maxHops: Int {
        topologyNodes.map(\.hopCount).max() ?? 0
    }

    private var sosActive: Bool {
        EmergencyMode.shared.isActive
    }

    /// Compute hop path from self to a destination node via MeshIntelligence.
    private func computeHopPath(to node: TopologyNode) {
        Task {
            guard let path = await appState.meshIntelligence.pathTo(destination: node.id) else {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) { activeHopPath = nil }
                }
                return
            }
            // Build link quality for each segment: self->first, first->second, etc.
            var links: [HopPath.Link] = []
            let selfID = appState.localPeerID
            var prevID = selfID
            for peerID in path {
                let quality = await appState.meshIntelligence.linkQuality(from: prevID, to: peerID)
                links.append(HopPath.Link(fromID: prevID, toID: peerID, quality: quality))
                prevID = peerID
            }
            let hopPath = HopPath(peerIDs: path, links: links, destinationName: node.name)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) { activeHopPath = hopPath }
            }
        }
    }

    /// Build peer pins from beacon data for the geographic map view.
    private var peerPins: [PeerPin] {
        let beaconNodes = appState.meshBeacon.sortedNodes
        let peers = appState.channelManager.activeChannel?.peers ?? []
        let peerTransport: [String: ChirpPeer.TransportType] = Dictionary(
            peers.map { ($0.id, $0.transportType) },
            uniquingKeysWith: { _, last in last }
        )

        return beaconNodes.compactMap { beacon in
            guard let lat = beacon.latitude, let lon = beacon.longitude else { return nil }
            let isStale = Date().timeIntervalSince(beacon.lastSeen) > 10
            let transport = peerTransport[beacon.id] ?? (beacon.isDirect ? .multipeer : .multipeer)
            return PeerPin(
                id: beacon.id,
                name: beacon.name,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                transportType: transport,
                isStale: isStale
            )
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Dark background gradient
            LinearGradient(
                colors: [Constants.Colors.backgroundPrimary, Constants.Colors.slate900],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Underline tab picker
                HStack(spacing: 0) {
                    ForEach(MapTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedTab = tab
                            }
                        } label: {
                            VStack(spacing: Constants.Layout.smallSpacing) {
                                Text(tab.rawValue)
                                    .font(.system(size: 15, weight: selectedTab == tab ? .semibold : .medium))
                                    .foregroundStyle(selectedTab == tab ? Constants.Colors.textPrimary : Constants.Colors.slate500)

                                ZStack {
                                    Rectangle()
                                        .fill(Color.clear)
                                        .frame(height: 2)

                                    if selectedTab == tab {
                                        Rectangle()
                                            .fill(Constants.Colors.blue500)
                                            .frame(height: 2)
                                            .matchedGeometryEffect(id: "meshUnderline", in: meshUnderline)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Constants.Layout.horizontalPadding)
                .padding(.top, Constants.Layout.smallSpacing)
                .padding(.bottom, 4)

                // Content
                switch selectedTab {
                case .topology:
                    topologyContent
                case .map:
                    geoMapContent
                }
            }

            // SOS badge at top (above picker)
            if sosActive {
                VStack {
                    TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
                        let phase = timeline.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 1.0)
                        SOSBadge(pulsePhase: phase)
                    }
                    .padding(.top, 52)
                    Spacer()
                }
            }
        }
        .accessibilityIdentifier(AccessibilityID.meshMap)
        .navigationTitle("Mesh Network")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if selectedTab == .map {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showOfflineMapSheet = true
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(amber)
                    }
                    .accessibilityLabel("Download offline maps")
                }
            }
        }
        .sheet(item: $selectedNode) { node in
            NodeDetailSheet(node: node)
                .presentationDetents([.medium])
                .presentationDragIndicator(.hidden)
                .onDisappear {
                    withAnimation(.easeInOut(duration: 0.3)) { activeHopPath = nil }
                }
        }
        .sheet(isPresented: $showOfflineMapSheet) {
            OfflineMapDownloadSheet()
                .environment(appState)
        }
        .task {
            // Periodically fetch health score from MeshIntelligence (actor)
            while !Task.isCancelled {
                let score = await appState.meshIntelligence.meshHealthScore
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        cachedHealthScore = score
                    }
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: - Topology Content

    private var topologyContent: some View {
        ZStack {
            GeometryReader { geo in
                let size = geo.size
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxRadius = min(size.width, size.height) * 0.40
                let maxHop = max(3, (topologyNodes.map(\.hopCount).max() ?? 1) + 1)

                // Animated canvas layer (lines, rings, grid, pulses)
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let phase = timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 3.0) / 3.0

                    TopologyCanvas(
                        size: size,
                        nodes: topologyNodes,
                        pulsePhase: phase,
                        meshHealthScore: cachedHealthScore,
                        sosActive: sosActive,
                        hopPath: activeHopPath,
                        selfID: appState.localPeerID
                    )
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Mesh topology map with \(topologyNodes.count) peer\(topologyNodes.count == 1 ? "" : "s")")
                .accessibilityIdentifier(AccessibilityID.meshMapCanvas)

                // Center node (self)
                VStack(spacing: 4) {
                    NodeBubble(
                        node: TopologyNode(
                            id: "self",
                            name: appState.callsign,
                            hopCount: 0,
                            isConnected: true,
                            batteryLevel: 1.0,
                            signalQuality: 1.0,
                            lastSeen: Date(),
                            neighborIDs: []
                        ),
                        isCenter: true
                    )
                }
                .position(center)

                // Health score overlaid at center, offset below the node
                HealthScoreView(score: cachedHealthScore)
                    .position(x: center.x, y: center.y + 52)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Mesh health score: \(Int(cachedHealthScore * 100)) percent")
                    .accessibilityIdentifier(AccessibilityID.meshHealthScore)

                // "You" label
                Text("You")
                    .font(Constants.Typography.badge)
                    .foregroundStyle(amber.opacity(0.6))
                    .position(x: center.x, y: center.y + 80)

                // Peer nodes arranged by hop ring
                ForEach(topologyNodes) { node in
                    let point = nodePosition(
                        for: node,
                        center: center,
                        maxRadius: maxRadius,
                        maxHop: maxHop,
                        allNodes: topologyNodes
                    )

                    VStack(spacing: 2) {
                        NodeBubble(node: node, isCenter: false)

                        Text(node.name.split(separator: " ").first.map(String.init) ?? node.name)
                            .font(Constants.Typography.badge)
                            .foregroundStyle(node.isDirect ? Constants.Colors.textSecondary : Constants.Colors.textTertiary)
                            .lineLimit(1)
                    }
                    .position(point)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(node.name), \(node.hopCount) hop\(node.hopCount == 1 ? "" : "s") away, signal \(node.signalQuality > 0.7 ? "good" : node.signalQuality > 0.3 ? "fair" : "poor")")
                    .accessibilityHint("Tap for details")
                    .accessibilityAddTraits(.isButton)
                    .onTapGesture {
                        selectedNode = node
                        computeHopPath(to: node)
                    }
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: topologyNodes)
                }

                // Empty state
                if topologyNodes.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()

                        scanningRipple
                            .frame(height: 120)

                        Text("Scanning for mesh peers...")
                            .font(Constants.Typography.body)
                            .foregroundStyle(Constants.Colors.textSecondary)

                        Text("Nearby ChirpChirps devices will appear here")
                            .font(Constants.Typography.caption)
                            .foregroundStyle(Constants.Colors.textTertiary)

                        Spacer()
                            .frame(height: 100)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Stats bar at bottom
            VStack {
                Spacer()
                LiveStatsBar(
                    stats: appState.meshStats,
                    maxHops: maxHops
                )
                .accessibilityIdentifier(AccessibilityID.meshStatsBar)
            }
        }
    }

    // MARK: - Geographic Map Content

    /// Build geographic hop segments from the active hop path and peer pin coordinates.
    private var geoHopSegments: [GeoHopSegment] {
        guard let hopPath = activeHopPath else { return [] }
        let pinMap = Dictionary(peerPins.map { ($0.id, $0.coordinate) }, uniquingKeysWith: { _, b in b })
        var segments: [GeoHopSegment] = []
        for link in hopPath.links {
            let fromCoord: CLLocationCoordinate2D?
            if link.fromID == appState.localPeerID {
                fromCoord = appState.locationService.currentLocation?.coordinate
            } else {
                fromCoord = pinMap[link.fromID]
            }
            let toCoord = pinMap[link.toID]
            guard let from = fromCoord, let to = toCoord else { continue }
            segments.append(GeoHopSegment(from: from, to: to, quality: link.quality))
        }
        return segments
    }

    /// Build dead drop pins from the DeadDropService.
    private var deadDropMapPins: [DeadDropPin] {
        appState.deadDropService.allActiveDrops.compactMap { drop in
            guard let decoded = Geohash.decode(drop.geohashPrefix) else { return nil }
            let coord = CLLocationCoordinate2D(latitude: decoded.latitude, longitude: decoded.longitude)
            return DeadDropPin(
                id: drop.id,
                coordinate: coord,
                geohashPrefix: drop.geohashPrefix,
                isTimeLocked: drop.isTimeLocked,
                timeLockDate: drop.timeLockDate,
                expiresAt: drop.expiresAt,
                senderName: drop.senderName,
                isPickedUp: appState.deadDropService.pickedUpMessages[drop.id] != nil
            )
        }
    }

    /// Build peer movement trails from LighthouseDatabase breadcrumbs.
    private var peerMovementTrails: [PeerTrail] {
        guard let db = appState.lighthouseService.database else { return [] }
        let peerIDs = db.allBreadcrumbPeerIDs()
        return peerIDs.compactMap { peerID in
            let crumbs = db.recentBreadcrumbs(forPeer: peerID, limit: 50)
            guard crumbs.count >= 2 else { return nil }
            let coords = crumbs.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            let timestamps = crumbs.map(\.timestamp)
            return PeerTrail(peerID: peerID, coordinates: coords, timestamps: timestamps)
        }
    }

    private var geoMapContent: some View {
        ZStack {
            GeoMapView(
                userLocation: appState.locationService.currentLocation?.coordinate,
                peers: peerPins,
                hopSegments: geoHopSegments,
                hopCount: activeHopPath?.hopCount ?? 0,
                deadDropPins: deadDropMapPins,
                peerTrails: peerMovementTrails
            )
            .ignoresSafeArea(edges: .bottom)

            // Stats bar at bottom
            VStack {
                Spacer()
                LiveStatsBar(
                    stats: appState.meshStats,
                    maxHops: maxHops
                )
                .accessibilityIdentifier(AccessibilityID.meshStatsBar)
            }
        }
    }

    // MARK: - Scanning Ripple (empty state)

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
}
