import Foundation
import os
import WiFiAware

@Observable
@MainActor
final class WiFiAwareManager {

    private let logger = Logger(subsystem: "com.chirpchirp.app", category: "WiFiAwareManager")

    private(set) var pairedDevices: [WAPairedDevice] = []
    private(set) var isSupported: Bool = false

    private var observationTask: Task<Void, Never>?

    init() {
        isSupported = WACapabilities.supportedFeatures.contains(.wifiAware)
        logger.info("Wi-Fi Aware supported: \(self.isSupported)")
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: - Paired Device Observation

    func startObservingPairedDevices() async {
        observationTask?.cancel()

        guard isSupported else {
            logger.warning("Cannot observe paired devices — Wi-Fi Aware not supported")
            return
        }

        observationTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await devicesDict in WAPairedDevice.allDevices {
                    guard !Task.isCancelled else { break }
                    self.pairedDevices = Array(devicesDict.values)
                    self.logger.debug("Paired devices updated: \(devicesDict.count) device(s)")
                }
            } catch {
                self.logger.error("Paired device observation failed: \(error.localizedDescription)")
            }
        }
    }

    func stopObservingPairedDevices() {
        observationTask?.cancel()
        observationTask = nil
    }
}
