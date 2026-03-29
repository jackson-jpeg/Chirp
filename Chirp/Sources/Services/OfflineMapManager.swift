import CoreLocation
import Foundation
import MapLibre
import OSLog

// MARK: - Offline Region Model

struct OfflineRegion: Identifiable, Sendable {
    let id: String
    let name: String
    let sizeBytes: UInt64
    let date: Date
    let center: CLLocationCoordinate2D
    let radiusKm: Double
}

// MARK: - Offline Map Manager

@Observable
@MainActor
final class OfflineMapManager: NSObject {

    // MARK: - Public State

    private(set) var downloadProgress: Double = 0.0
    private(set) var isDownloading: Bool = false
    private(set) var downloadedRegions: [OfflineRegion] = []

    // MARK: - Private

    private let logger = Logger(subsystem: Constants.subsystem, category: "OfflineMap")
    private var activePack: MLNOfflinePack?

    /// OpenFreeMap Liberty style — free, no API key required.
    static let styleURL = URL(string: "https://tiles.openfreemap.org/styles/liberty/style.json")!

    // MARK: - Init

    override init() {
        super.init()
        loadExistingRegions()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(packProgressChanged(_:)),
            name: .MLNOfflinePackProgressChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(packError(_:)),
            name: .MLNOfflinePackError,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Download

    /// Download map tiles for a circular region at zoom levels 0-15.
    func downloadRegion(center: CLLocationCoordinate2D, radiusKm: Double) {
        guard !isDownloading else {
            logger.warning("Download already in progress")
            return
        }

        let bounds = boundingBox(center: center, radiusKm: radiusKm)
        let region = MLNTilePyramidOfflineRegion(
            styleURL: Self.styleURL,
            bounds: bounds,
            fromZoomLevel: 0,
            toZoomLevel: 15
        )

        let name = String(
            format: "%.2f, %.2f (%.0f km)",
            center.latitude,
            center.longitude,
            radiusKm
        )

        let metadata: [String: Any] = [
            "name": name,
            "date": ISO8601DateFormatter().string(from: Date()),
            "centerLat": center.latitude,
            "centerLon": center.longitude,
            "radiusKm": radiusKm
        ]

        guard let metadataData = try? JSONSerialization.data(withJSONObject: metadata) else {
            logger.error("Failed to serialize region metadata")
            return
        }

        isDownloading = true
        downloadProgress = 0.0

        MLNOfflineStorage.shared.addPack(for: region, withContext: metadataData) { [weak self] pack, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.logger.error("Failed to create offline pack: \(error.localizedDescription)")
                    self.isDownloading = false
                    return
                }
                guard let pack else {
                    self.logger.error("Offline pack creation returned nil")
                    self.isDownloading = false
                    return
                }
                self.activePack = pack
                pack.resume()
                self.logger.info("Started downloading region: \(name)")
            }
        }
    }

    /// Estimate download size in MB for a region.
    static func estimateSizeMB(radiusKm: Double, maxZoom: Int = 15) -> Double {
        // Rough estimate: ~25 KB per tile at mid-zoom, tile count grows 4x per zoom level.
        // For a region of radius R km, tile count at zoom z is approximately (2R / tileSize(z))^2.
        let earthCircumferenceKm = 40_075.0
        var totalTiles = 0.0
        for zoom in 0...maxZoom {
            let tileWidthKm = earthCircumferenceKm / pow(2.0, Double(zoom))
            let tilesAcross = max(1.0, (2.0 * radiusKm) / tileWidthKm)
            totalTiles += tilesAcross * tilesAcross
        }
        let avgTileSizeKB = 20.0
        return (totalTiles * avgTileSizeKB) / 1024.0
    }

    // MARK: - Delete

    func deleteRegion(id: String) {
        guard let packs = MLNOfflineStorage.shared.packs else { return }

        for pack in packs {
            let regionID = self.regionID(for: pack)
            if regionID == id {
                MLNOfflineStorage.shared.removePack(pack) { [weak self] error in
                    Task { @MainActor [weak self] in
                        if let error {
                            self?.logger.error("Failed to delete region: \(error.localizedDescription)")
                            return
                        }
                        self?.downloadedRegions.removeAll { $0.id == id }
                        self?.logger.info("Deleted offline region: \(id)")
                    }
                }
                return
            }
        }
    }

    // MARK: - Load Existing Regions

    private func loadExistingRegions() {
        guard let packs = MLNOfflineStorage.shared.packs else { return }

        downloadedRegions = packs.compactMap { pack in
            let context = pack.context
            guard let metadata = try? JSONSerialization.jsonObject(with: context) as? [String: Any],
                  let name = metadata["name"] as? String else {
                return nil
            }

            let dateString = metadata["date"] as? String ?? ""
            let date = ISO8601DateFormatter().date(from: dateString) ?? Date()
            let centerLat = metadata["centerLat"] as? Double ?? 0
            let centerLon = metadata["centerLon"] as? Double ?? 0
            let radiusKm = metadata["radiusKm"] as? Double ?? 0

            let progress = pack.progress
            let sizeBytes = progress.countOfBytesCompleted

            return OfflineRegion(
                id: regionID(for: pack),
                name: name,
                sizeBytes: UInt64(max(0, sizeBytes)),
                date: date,
                center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                radiusKm: radiusKm
            )
        }

        // Mark offline storage excluded from backup
        excludeFromBackup()
    }

    // MARK: - Progress Notifications

    @objc private nonisolated func packProgressChanged(_ notification: Notification) {
        guard let pack = notification.object as? MLNOfflinePack else { return }
        let progress = pack.progress
        let completed = Double(progress.countOfResourcesCompleted)
        let expected = Double(progress.countOfResourcesExpected)

        Task { @MainActor [weak self] in
            guard let self else { return }

            if expected > 0 {
                self.downloadProgress = min(1.0, completed / expected)
            }

            if progress.countOfResourcesCompleted >= progress.countOfResourcesExpected,
               progress.countOfResourcesExpected > 0 {
                self.isDownloading = false
                self.activePack = nil
                self.downloadProgress = 1.0
                self.loadExistingRegions()
                self.logger.info("Offline region download complete (\(progress.countOfResourcesCompleted) resources)")
            }
        }
    }

    @objc private nonisolated func packError(_ notification: Notification) {
        if let error = notification.userInfo?[MLNOfflinePackUserInfoKey.error] as? NSError {
            Task { @MainActor [weak self] in
                self?.logger.error("Offline pack error: \(error.localizedDescription)")
                self?.isDownloading = false
            }
        }
    }

    // MARK: - Helpers

    private func regionID(for pack: MLNOfflinePack) -> String {
        let context = pack.context
        guard let metadata = try? JSONSerialization.jsonObject(with: context) as? [String: Any],
              let name = metadata["name"] as? String,
              let dateStr = metadata["date"] as? String else {
            return UUID().uuidString
        }
        return "\(name)-\(dateStr)"
    }

    private func boundingBox(center: CLLocationCoordinate2D, radiusKm: Double) -> MLNCoordinateBounds {
        let earthRadiusKm = 6_371.0
        let latDelta = (radiusKm / earthRadiusKm) * (180.0 / .pi)
        let lonDelta = latDelta / cos(center.latitude * .pi / 180.0)

        let sw = CLLocationCoordinate2D(
            latitude: center.latitude - latDelta,
            longitude: center.longitude - lonDelta
        )
        let ne = CLLocationCoordinate2D(
            latitude: center.latitude + latDelta,
            longitude: center.longitude + lonDelta
        )
        return MLNCoordinateBounds(sw: sw, ne: ne)
    }

    /// Exclude MapLibre offline database from iCloud backup.
    private func excludeFromBackup() {
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard var url = cachesURL else { return }
        url.appendPathComponent(".maplibre")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? url.setResourceValues(resourceValues)
    }
}
