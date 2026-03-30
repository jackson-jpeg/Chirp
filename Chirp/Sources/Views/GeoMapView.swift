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

struct GeoMapView: UIViewRepresentable {
    let userLocation: CLLocationCoordinate2D?
    let peers: [PeerPin]
    var isInteractive: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero)
        mapView.styleURL = OfflineMapManager.styleURL
        mapView.showsUserLocation = true
        mapView.showsUserHeadingIndicator = true

        // Dark appearance
        mapView.tintColor = UIColor(Constants.Colors.amber)

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

    // MARK: - Coordinator

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var annotationMap: [String: MLNPointAnnotation] = [:]
        var peerData: [String: PeerPin] = [:]
        weak var mapView: MLNMapView?

        // MLNMapViewDelegate always calls this on the main thread.
        // Cache peer data outside the MainActor closure to avoid sending self.
        nonisolated func mapView(_ mapView: MLNMapView, viewFor annotation: any MLNAnnotation) -> MLNAnnotationView? {
            nonisolated(unsafe) let peers = peerData
            guard let pointAnnotation = annotation as? MLNPointAnnotation,
                  let peerID = pointAnnotation.subtitle,
                  let peer = peers[peerID] else {
                return nil
            }

            let reuseID = "peer-\(peer.id)"
            let color = pinColor(for: peer)

            return MainActor.assumeIsolated {
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID)

                if view == nil {
                    view = MLNAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
                    view?.frame = CGRect(x: 0, y: 0, width: 28, height: 28)

                    let dot = UIView(frame: CGRect(x: 4, y: 4, width: 20, height: 20))
                    dot.layer.cornerRadius = 10
                    dot.tag = 100
                    view?.addSubview(dot)

                    let border = UIView(frame: CGRect(x: 2, y: 2, width: 24, height: 24))
                    border.layer.cornerRadius = 12
                    border.layer.borderWidth = 2
                    border.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
                    border.backgroundColor = .clear
                    border.tag = 101
                    view?.addSubview(border)
                }

                if let dot = view?.viewWithTag(100) {
                    dot.backgroundColor = color
                }

                return view
            }
        }

        func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: any MLNAnnotation) -> Bool {
            true
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
