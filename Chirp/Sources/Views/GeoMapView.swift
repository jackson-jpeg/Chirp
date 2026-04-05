import CoreLocation
@preconcurrency import MapLibre
import SwiftUI

// MARK: - Peer Pin Data

struct PeerPin: Equatable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let transportType: ChirpPeer.TransportType
    let isStale: Bool

    static func == (lhs: PeerPin, rhs: PeerPin) -> Bool {
        lhs.id == rhs.id
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.transportType == rhs.transportType
            && lhs.isStale == rhs.isStale
    }
}

// MARK: - Dead Drop Pin Data

struct DeadDropPin: Equatable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let geohashPrefix: String
    let isTimeLocked: Bool
    let timeLockDate: String?
    let expiresAt: Date
    let senderName: String
    let isPickedUp: Bool

    /// Approximate radius in meters based on geohash prefix length.
    /// Precision 4 chars ~ 39 km x 20 km cell, but the full drop uses precision 7 (~153m).
    var proximityRadiusMeters: Double {
        // The drop is encrypted at precision 7. The prefix is 4 chars for routing only.
        // Precision 7 geohash cell is approximately 153m x 153m.
        153.0
    }

    /// Human-readable proximity description.
    var proximityDescription: String {
        "~\(Int(proximityRadiusMeters))m radius"
    }

    /// Time-lock status description.
    var timeLockStatus: String {
        guard isTimeLocked, let dateStr = timeLockDate else {
            return "Available"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        if let lockDate = formatter.date(from: dateStr), lockDate > Date() {
            return "Locked until \(dateStr)"
        }
        return "Available"
    }

    /// Expiry countdown description.
    var expiryDescription: String {
        let remaining = expiresAt.timeIntervalSinceNow
        if remaining <= 0 { return "Expired" }
        let hours = Int(remaining / 3600)
        let minutes = Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours > 0 {
            return "\(hours)h \(minutes)m remaining"
        }
        return "\(minutes)m remaining"
    }

    static func == (lhs: DeadDropPin, rhs: DeadDropPin) -> Bool {
        lhs.id == rhs.id
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.isTimeLocked == rhs.isTimeLocked
            && lhs.isPickedUp == rhs.isPickedUp
    }
}

// MARK: - Peer Trail Data

struct PeerTrail: Equatable {
    let peerID: String
    let coordinates: [CLLocationCoordinate2D]
    let timestamps: [Date]

    static func == (lhs: PeerTrail, rhs: PeerTrail) -> Bool {
        lhs.peerID == rhs.peerID && lhs.coordinates.count == rhs.coordinates.count
    }
}

// MARK: - GeoMapView

/// A single segment of a hop path for geographic overlay rendering.
struct GeoHopSegment: Equatable {
    let from: CLLocationCoordinate2D
    let to: CLLocationCoordinate2D
    let quality: Double  // 0-1

    static func == (lhs: GeoHopSegment, rhs: GeoHopSegment) -> Bool {
        lhs.from.latitude == rhs.from.latitude
            && lhs.from.longitude == rhs.from.longitude
            && lhs.to.latitude == rhs.to.latitude
            && lhs.to.longitude == rhs.to.longitude
            && lhs.quality == rhs.quality
    }
}

struct GeoMapView: UIViewRepresentable {
    let userLocation: CLLocationCoordinate2D?
    let peers: [PeerPin]
    var isInteractive: Bool = true
    var hopSegments: [GeoHopSegment] = []
    var hopCount: Int = 0
    var deadDropPins: [DeadDropPin] = []
    var peerTrails: [PeerTrail] = []

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), styleURL: OfflineMapManager.styleURL)
        mapView.showsUserLocation = true
        mapView.showsUserHeadingIndicator = true
        mapView.automaticallyAdjustsContentInset = false

        // Dark appearance
        mapView.tintColor = UIColor(Constants.Colors.amber)
        mapView.backgroundColor = UIColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1)

        if !isInteractive {
            mapView.isScrollEnabled = false
            mapView.isZoomEnabled = false
            mapView.isRotateEnabled = false
            mapView.isPitchEnabled = false
        }

        // Set initial camera to user location if available
        if let coord = userLocation {
            mapView.setCenter(coord, zoomLevel: 13, animated: false)
        }

        mapView.delegate = context.coordinator
        context.coordinator.mapView = mapView

        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        updateAnnotations(mapView: mapView, coordinator: context.coordinator)
        updateHopPathOverlay(mapView: mapView, coordinator: context.coordinator)
        updateDeadDropAnnotations(mapView: mapView, coordinator: context.coordinator)
        updatePeerTrailOverlays(mapView: mapView, coordinator: context.coordinator)
    }

    // MARK: - Annotations

    private func updateAnnotations(mapView: MLNMapView, coordinator: Coordinator) {
        // Remove stale annotations
        let existingIDs = Set(coordinator.annotationMap.keys)
        let currentIDs = Set(peers.map(\.id))

        let toRemove = existingIDs.subtracting(currentIDs)
        for id in toRemove {
            if let annotation = coordinator.annotationMap.removeValue(forKey: id) {
                mapView.removeAnnotation(annotation)
            }
        }

        // Add or update peer annotations
        for peer in peers {
            if let existing = coordinator.annotationMap[peer.id] {
                // Update position if changed
                if existing.coordinate.latitude != peer.coordinate.latitude
                    || existing.coordinate.longitude != peer.coordinate.longitude {
                    existing.coordinate = peer.coordinate
                }
                existing.title = peer.name
            } else {
                let annotation = MLNPointAnnotation()
                annotation.coordinate = peer.coordinate
                annotation.title = peer.name
                annotation.subtitle = peer.id
                mapView.addAnnotation(annotation)
                coordinator.annotationMap[peer.id] = annotation
            }

            // Store peer data for coloring
            coordinator.peerData[peer.id] = peer
        }
    }

    // MARK: - Hop Path Overlay

    private func updateHopPathOverlay(mapView: MLNMapView, coordinator: Coordinator) {
        // Remove existing hop path polylines
        for polyline in coordinator.hopPolylines {
            mapView.removeAnnotation(polyline)
        }
        coordinator.hopPolylines.removeAll()

        if let badge = coordinator.hopBadgeAnnotation {
            mapView.removeAnnotation(badge)
            coordinator.hopBadgeAnnotation = nil
        }

        guard !hopSegments.isEmpty else { return }

        // Draw each segment as a colored polyline
        for segment in hopSegments {
            var coords = [segment.from, segment.to]
            let polyline = MLNPolyline(coordinates: &coords, count: 2)
            // Encode quality in the title so the delegate can read it
            polyline.title = "hop-\(String(format: "%.2f", segment.quality))"
            mapView.addAnnotation(polyline)
            coordinator.hopPolylines.append(polyline)
        }

        // Add hop count badge at the destination (last segment endpoint)
        if hopCount > 0, let lastSeg = hopSegments.last {
            let badge = MLNPointAnnotation()
            badge.coordinate = lastSeg.to
            badge.title = "hop-badge"
            badge.subtitle = "\(hopCount)"
            mapView.addAnnotation(badge)
            coordinator.hopBadgeAnnotation = badge
        }
    }

    // MARK: - Dead Drop Annotations

    private func updateDeadDropAnnotations(mapView: MLNMapView, coordinator: Coordinator) {
        // Remove stale dead drop annotations
        let existingIDs = Set(coordinator.deadDropAnnotationMap.keys)
        let currentIDs = Set(deadDropPins.map(\.id))

        let toRemove = existingIDs.subtracting(currentIDs)
        for id in toRemove {
            if let annotation = coordinator.deadDropAnnotationMap.removeValue(forKey: id) {
                mapView.removeAnnotation(annotation)
            }
        }

        // Add or update dead drop annotations
        for pin in deadDropPins {
            if let existing = coordinator.deadDropAnnotationMap[pin.id] {
                if existing.coordinate.latitude != pin.coordinate.latitude
                    || existing.coordinate.longitude != pin.coordinate.longitude {
                    existing.coordinate = pin.coordinate
                }
            } else {
                let annotation = MLNPointAnnotation()
                annotation.coordinate = pin.coordinate
                annotation.title = "deaddrop-\(pin.id.uuidString)"
                annotation.subtitle = pin.id.uuidString
                mapView.addAnnotation(annotation)
                coordinator.deadDropAnnotationMap[pin.id] = annotation
            }

            coordinator.deadDropData[pin.id] = pin
        }
    }

    // MARK: - Peer Trail Overlays

    /// Trail color palette — one color per peer, cycling.
    static let trailPalette: [UIColor] = [
        UIColor(red: 0.25, green: 0.61, blue: 0.97, alpha: 1.0),  // blue
        UIColor(red: 0.56, green: 0.87, blue: 0.36, alpha: 1.0),  // green
        UIColor(red: 0.98, green: 0.47, blue: 0.30, alpha: 1.0),  // orange
        UIColor(red: 0.78, green: 0.38, blue: 0.95, alpha: 1.0),  // purple
        UIColor(red: 0.95, green: 0.77, blue: 0.26, alpha: 1.0),  // yellow
        UIColor(red: 0.36, green: 0.91, blue: 0.84, alpha: 1.0),  // teal
    ]

    private func updatePeerTrailOverlays(mapView: MLNMapView, coordinator: Coordinator) {
        // Remove existing trail polylines
        for polyline in coordinator.trailPolylines {
            mapView.removeAnnotation(polyline)
        }
        coordinator.trailPolylines.removeAll()
        coordinator.trailColorMap.removeAll()

        guard !peerTrails.isEmpty else { return }

        for (trailIndex, trail) in peerTrails.enumerated() {
            guard trail.coordinates.count >= 2 else { continue }

            let colorIndex = trailIndex % Self.trailPalette.count
            let baseColor = Self.trailPalette[colorIndex]

            // Draw trail as segments with decreasing opacity (recent = opaque, old = faded).
            // Each segment is a 2-point polyline so we can vary opacity per segment.
            let totalSegments = trail.coordinates.count - 1
            for i in 0..<totalSegments {
                var segCoords = [trail.coordinates[i], trail.coordinates[i + 1]]
                let polyline = MLNPolyline(coordinates: &segCoords, count: 2)

                // Opacity: segment 0 (oldest) = 0.2, last segment (newest) = 1.0
                let progress = Double(i) / Double(max(1, totalSegments - 1))
                let opacity = 0.2 + 0.8 * progress

                // Encode trail metadata in title: "trail-<colorIndex>-<opacity>"
                polyline.title = "trail-\(colorIndex)-\(String(format: "%.2f", opacity))"
                mapView.addAnnotation(polyline)
                coordinator.trailPolylines.append(polyline)
                coordinator.trailColorMap[ObjectIdentifier(polyline)] = (baseColor, CGFloat(opacity))
            }
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MLNMapViewDelegate {
        var annotationMap: [String: MLNPointAnnotation] = [:]
        var peerData: [String: PeerPin] = [:]
        weak var mapView: MLNMapView?
        var hopPolylines: [MLNPolyline] = []
        var hopBadgeAnnotation: MLNPointAnnotation?

        // Dead drop state
        var deadDropAnnotationMap: [UUID: MLNPointAnnotation] = [:]
        var deadDropData: [UUID: DeadDropPin] = [:]

        // Trail state
        var trailPolylines: [MLNPolyline] = []
        var trailColorMap: [ObjectIdentifier: (UIColor, CGFloat)] = [:]  // polyline -> (color, opacity)

        func mapView(_ mapView: MLNMapView, viewFor annotation: any MLNAnnotation) -> MLNAnnotationView? {
            // Hop count badge
            if let pointAnnotation = annotation as? MLNPointAnnotation,
               pointAnnotation.title == "hop-badge" {
                let reuseID = "hop-badge"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID)
                if view == nil {
                    view = MLNAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
                    view?.frame = CGRect(x: 0, y: 0, width: 28, height: 28)

                    let bg = UIView(frame: CGRect(x: 0, y: 0, width: 28, height: 28))
                    bg.backgroundColor = UIColor(Constants.Colors.amber)
                    bg.layer.cornerRadius = 14
                    bg.tag = 200
                    view?.addSubview(bg)

                    let label = UILabel(frame: CGRect(x: 0, y: 0, width: 28, height: 28))
                    label.textAlignment = .center
                    label.font = UIFont.systemFont(ofSize: 12, weight: .bold)
                    label.textColor = .black
                    label.tag = 201
                    view?.addSubview(label)
                }
                if let label = view?.viewWithTag(201) as? UILabel {
                    label.text = pointAnnotation.subtitle
                }
                return view
            }

            // Dead drop pin — diamond-shaped with lock icon for distinct visibility
            if let pointAnnotation = annotation as? MLNPointAnnotation,
               let title = pointAnnotation.title,
               title.hasPrefix("deaddrop-"),
               let idString = pointAnnotation.subtitle,
               let dropID = UUID(uuidString: idString),
               let dropPin = deadDropData[dropID] {
                let reuseID = "deaddrop"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID)

                if view == nil {
                    view = MLNAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
                    view?.frame = CGRect(x: 0, y: 0, width: 36, height: 36)

                    // Diamond-shaped background (rotated square)
                    let bg = UIView(frame: CGRect(x: 4, y: 4, width: 28, height: 28))
                    bg.layer.cornerRadius = 6
                    bg.transform = CGAffineTransform(rotationAngle: .pi / 4)
                    bg.tag = 300
                    view?.addSubview(bg)

                    // Lock icon (not rotated — sits centered on top)
                    let iconView = UIImageView(frame: CGRect(x: 10, y: 10, width: 16, height: 16))
                    iconView.contentMode = .scaleAspectFit
                    iconView.tintColor = .black
                    iconView.tag = 301
                    view?.addSubview(iconView)

                    // Outer glow ring for time-locked state
                    let ring = UIView(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
                    ring.layer.cornerRadius = 18
                    ring.layer.borderWidth = 2
                    ring.backgroundColor = .clear
                    ring.tag = 302
                    view?.addSubview(ring)
                }

                // Configure colors based on state
                let isExpired = dropPin.expiresAt < Date()
                let bgColor: UIColor = isExpired
                    ? UIColor(white: 0.4, alpha: 1.0)
                    : dropPin.isTimeLocked
                        ? UIColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1.0)  // deeper amber for time-locked
                        : UIColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 1.0)  // amber/gold

                if let bg = view?.viewWithTag(300) {
                    bg.backgroundColor = bgColor
                    bg.layer.shadowColor = bgColor.cgColor
                    bg.layer.shadowOpacity = isExpired ? 0 : 0.6
                    bg.layer.shadowRadius = 6
                    bg.layer.shadowOffset = .zero
                }

                if let iconView = view?.viewWithTag(301) as? UIImageView {
                    let symbolName = dropPin.isPickedUp ? "lock.open.fill" : "lock.fill"
                    iconView.image = UIImage(systemName: symbolName)
                    iconView.tintColor = isExpired ? .darkGray : .black
                }

                if let ring = view?.viewWithTag(302) {
                    ring.layer.borderColor = dropPin.isTimeLocked
                        ? UIColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 0.8).cgColor
                        : UIColor.white.withAlphaComponent(0.2).cgColor
                    ring.isHidden = !dropPin.isTimeLocked
                }

                view?.isAccessibilityElement = true
                view?.accessibilityLabel = "Dead drop from \(dropPin.senderName), \(dropPin.timeLockStatus), \(dropPin.expiryDescription)"

                return view
            }

            // Peer pin (existing logic)
            guard let pointAnnotation = annotation as? MLNPointAnnotation,
                  let peerID = pointAnnotation.subtitle,
                  let peer = peerData[peerID] else {
                return nil
            }

            let reuseID = "peer-\(peer.id)"
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID)

            if view == nil {
                // Taller frame to accommodate the name label below the dot
                view = MLNAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
                view?.frame = CGRect(x: 0, y: 0, width: 80, height: 44)
                view?.centerOffset = CGVector(dx: 0, dy: -8)

                let dot = UIView(frame: CGRect(x: 30, y: 0, width: 20, height: 20))
                dot.layer.cornerRadius = 10
                dot.tag = 100
                view?.addSubview(dot)

                let border = UIView(frame: CGRect(x: 28, y: -2, width: 24, height: 24))
                border.layer.cornerRadius = 12
                border.layer.borderWidth = 2
                border.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
                border.backgroundColor = .clear
                border.tag = 101
                view?.addSubview(border)

                // Name label below the dot
                let nameLabel = UILabel(frame: CGRect(x: 0, y: 22, width: 80, height: 18))
                nameLabel.textAlignment = .center
                nameLabel.font = UIFont.systemFont(ofSize: 10, weight: .semibold)
                nameLabel.textColor = .white
                nameLabel.layer.shadowColor = UIColor.black.cgColor
                nameLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
                nameLabel.layer.shadowOpacity = 0.8
                nameLabel.layer.shadowRadius = 2
                nameLabel.tag = 102
                view?.addSubview(nameLabel)
            }

            let color = pinColor(for: peer)
            if let dot = view?.viewWithTag(100) {
                dot.backgroundColor = color
                dot.alpha = peer.isStale ? 0.5 : 1.0
            }
            if let nameLabel = view?.viewWithTag(102) as? UILabel {
                nameLabel.text = peer.name
                nameLabel.alpha = peer.isStale ? 0.4 : 0.9
            }

            view?.isAccessibilityElement = true
            view?.accessibilityLabel = peer.isStale
                ? "\(peer.name), stale location"
                : "\(peer.name), connected via \(peer.transportType)"

            return view
        }

        func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: any MLNAnnotation) -> Bool {
            // Don't show callout for hop path elements
            if let point = annotation as? MLNPointAnnotation, point.title == "hop-badge" {
                return false
            }
            // Show callout for dead drop pins (will show detail popover)
            if let point = annotation as? MLNPointAnnotation,
               let title = point.title,
               title.hasPrefix("deaddrop-") {
                return true
            }
            return true
        }

        func mapView(_ mapView: MLNMapView, calloutViewFor annotation: any MLNAnnotation) -> MLNCalloutView? {
            // Custom callout for dead drop pins
            if let point = annotation as? MLNPointAnnotation,
               let title = point.title,
               title.hasPrefix("deaddrop-"),
               let idString = point.subtitle,
               let dropID = UUID(uuidString: idString),
               let dropPin = deadDropData[dropID] {
                return DeadDropCalloutView(pin: dropPin)
            }
            return nil
        }

        func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
            if let title = annotation.title {
                // Trail polylines
                if title.hasPrefix("trail-") {
                    let oid = ObjectIdentifier(annotation)
                    if let (color, _) = trailColorMap[oid] {
                        return color
                    }
                    // Fallback: parse color index from title
                    let parts = title.split(separator: "-")
                    if parts.count >= 2, let colorIndex = Int(parts[1]) {
                        return GeoMapView.trailPalette[colorIndex % GeoMapView.trailPalette.count]
                    }
                }

                // Hop polylines
                if title.hasPrefix("hop-") {
                    let qualityStr = title.replacingOccurrences(of: "hop-", with: "")
                    let quality = Double(qualityStr) ?? 0.5
                    if quality > 0.7 {
                        return UIColor(Constants.Colors.meshHealthGood)
                    } else if quality >= 0.4 {
                        return UIColor(Constants.Colors.meshHealthFair)
                    } else {
                        return UIColor(Constants.Colors.meshHealthPoor)
                    }
                }
            }
            return UIColor(Constants.Colors.amber)
        }

        func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat {
            if let title = annotation.title {
                if title.hasPrefix("hop-") { return 4.0 }
                if title.hasPrefix("trail-") { return 3.0 }
            }
            return 2.0
        }

        func mapView(_ mapView: MLNMapView, alphaForShapeAnnotation annotation: MLNShape) -> CGFloat {
            if let title = annotation.title {
                if title.hasPrefix("trail-") {
                    // Parse opacity from "trail-<colorIndex>-<opacity>"
                    let parts = title.split(separator: "-")
                    if parts.count >= 3, let opacity = Double(parts[2]) {
                        return CGFloat(opacity)
                    }
                    return 0.6
                }
                if title.hasPrefix("hop-") {
                    return 0.85
                }
            }
            return 1.0
        }

        private func pinColor(for peer: PeerPin) -> UIColor {
            if peer.isStale {
                return UIColor(white: 0.5, alpha: 1.0)
            }
            switch peer.transportType {
            case .wifiAware:
                return UIColor(Constants.Colors.amber)
            case .multipeer:
                return UIColor(Constants.Colors.electricGreen)
            case .both:
                return UIColor(Constants.Colors.electricGreen)
            }
        }
    }
}

// MARK: - Dead Drop Callout View

/// Custom callout view for dead drop pins showing proximity, time-lock, and expiry details.
final class DeadDropCalloutView: UIView, @preconcurrency MLNCalloutView {
    var representedObject: any MLNAnnotation
    var leftAccessoryView: UIView = UIView()
    var rightAccessoryView: UIView = UIView()
    weak var delegate: (any MLNCalloutViewDelegate)?
    var isAnchoredToAnnotation: Bool = true
    var dismissesAutomatically: Bool = true

    private let pin: DeadDropPin

    init(pin: DeadDropPin) {
        self.pin = pin
        // Use a dummy annotation — representedObject is set by MapLibre before presentation.
        let placeholder = MLNPointAnnotation()
        self.representedObject = placeholder
        super.init(frame: .zero)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = UIColor(red: 0.12, green: 0.15, blue: 0.22, alpha: 0.95)
        layer.cornerRadius = 10
        layer.borderWidth = 1
        layer.borderColor = UIColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 0.5).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.4
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 2)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])

        // Title
        let titleLabel = UILabel()
        titleLabel.text = "Dead Drop — \(pin.senderName)"
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = UIColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 1.0)
        stack.addArrangedSubview(titleLabel)

        // Proximity
        let proximityLabel = makeDetailLabel(
            icon: "location.circle",
            text: "Proximity: \(pin.proximityDescription)"
        )
        stack.addArrangedSubview(proximityLabel)

        // Time-lock
        let timeLockIcon = pin.isTimeLocked ? "clock.badge.lock.fill" : "clock"
        let timeLockLabel = makeDetailLabel(
            icon: timeLockIcon,
            text: pin.timeLockStatus
        )
        stack.addArrangedSubview(timeLockLabel)

        // Expiry
        let expiryLabel = makeDetailLabel(
            icon: "timer",
            text: pin.expiryDescription
        )
        stack.addArrangedSubview(expiryLabel)

        // Size to fit
        let targetSize = systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        frame = CGRect(origin: .zero, size: CGSize(
            width: max(180, targetSize.width),
            height: targetSize.height
        ))
    }

    private func makeDetailLabel(icon: String, text: String) -> UIView {
        let container = UIStackView()
        container.axis = .horizontal
        container.spacing = 5
        container.alignment = .center

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = UIColor(white: 0.7, alpha: 1.0)
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
        ])
        container.addArrangedSubview(iconView)

        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 11, weight: .regular)
        label.textColor = UIColor(white: 0.85, alpha: 1.0)
        container.addArrangedSubview(label)

        return container
    }

    func presentCallout(from rect: CGRect, in view: UIView, constrainedTo constrainedRect: CGRect, animated: Bool) {
        // Position above the annotation
        let x = rect.midX - bounds.width / 2
        let y = rect.minY - bounds.height - 10
        frame = CGRect(origin: CGPoint(x: x, y: y), size: bounds.size)
        view.addSubview(self)

        if animated {
            alpha = 0
            transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            UIView.animate(withDuration: 0.2) {
                self.alpha = 1
                self.transform = .identity
            }
        }
    }

    func dismissCallout(animated: Bool) {
        if animated {
            UIView.animate(withDuration: 0.15, animations: {
                self.alpha = 0
                self.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            }) { _ in
                self.removeFromSuperview()
            }
        } else {
            removeFromSuperview()
        }
    }
}
