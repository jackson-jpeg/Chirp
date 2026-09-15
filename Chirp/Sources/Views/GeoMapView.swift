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

    /// Whether to draw the blue "you are here" dot.
    ///
    /// Defaults to `false` and must stay that way. `MLNMapView` asks
    /// CoreLocation for authorization as soon as `showsUserLocation` is set,
    /// so switching this on unconditionally would put a system permission
    /// prompt behind the act of opening a map — exactly the automatic request
    /// the app must not make. The Map tab passes `true` only once permission
    /// has already been granted through the check-in sheet.
    var showsUserLocation: Bool = false

    /// Called when a peer pin is tapped, so the map can offer block/report.
    var onSelectPeer: ((PeerPin) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), styleURL: OfflineMapManager.styleURL)
        mapView.showsUserLocation = showsUserLocation
        mapView.showsUserHeadingIndicator = showsUserLocation
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
        // The struct is rebuilt on every render; hand the coordinator the
        // current closure so a tap never calls into a stale one.
        context.coordinator.onSelectPeer = onSelectPeer

        if mapView.showsUserLocation != showsUserLocation {
            mapView.showsUserLocation = showsUserLocation
            mapView.showsUserHeadingIndicator = showsUserLocation
        }

        updateAnnotations(mapView: mapView, coordinator: context.coordinator)
        updateHopPathOverlay(mapView: mapView, coordinator: context.coordinator)
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

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MLNMapViewDelegate {
        var annotationMap: [String: MLNPointAnnotation] = [:]
        var peerData: [String: PeerPin] = [:]
        weak var mapView: MLNMapView?
        var hopPolylines: [MLNPolyline] = []
        var hopBadgeAnnotation: MLNPointAnnotation?
        var onSelectPeer: ((PeerPin) -> Void)?

        func mapView(_ mapView: MLNMapView, didSelect annotation: any MLNAnnotation) {
            guard let point = annotation as? MLNPointAnnotation,
                  point.title != "hop-badge",
                  let peerID = point.subtitle,
                  let peer = peerData[peerID] else { return }
            onSelectPeer?(peer)
            // Deselect so the same pin can be tapped again without first
            // tapping elsewhere on the map.
            mapView.deselectAnnotation(annotation, animated: false)
        }

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
            return true
        }

        func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
            if let title = annotation.title {
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
            if let title = annotation.title, title.hasPrefix("hop-") {
                return 4.0
            }
            return 2.0
        }

        func mapView(_ mapView: MLNMapView, alphaForShapeAnnotation annotation: MLNShape) -> CGFloat {
            if let title = annotation.title, title.hasPrefix("hop-") {
                return 0.85
            }
            return 1.0
        }

        private func pinColor(for peer: PeerPin) -> UIColor {
            if peer.isStale {
                return UIColor(white: 0.5, alpha: 1.0)
            }
            return UIColor(Constants.Colors.electricGreen)
        }
    }
}
