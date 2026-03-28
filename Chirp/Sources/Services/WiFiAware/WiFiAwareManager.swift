import Foundation
import os
#if canImport(WiFiAware)
import WiFiAware
#endif

@Observable
final class WiFiAwareManager: @unchecked Sendable {

    private let logger = Logger(subsystem: "com.chirp.ptt", category: "WiFiAwareManager")

    // Use Any to avoid compile errors when WAPairedDevice is unavailable
    private(set) var pairedDevices: [Any] = []
    private(set) var isSupported: Bool = false

    private var observationTask: Task<Void, Never>?

    init() {
        #if canImport(WiFiAware)
        checkSupport()
        #else
        isSupported = false
        logger.info("Wi-Fi Aware not available on this platform")
        #endif
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: - Support Check

    #if canImport(WiFiAware)
    private func checkSupport() {
        Task {
            do {
                let capabilities = await WACapabilities.current
                isSupported = capabilities.isSupported
                logger.info("Wi-Fi Aware supported: \(self.isSupported)")
            }
        }
    }
    #endif

    // MARK: - Paired Device Observation

    func startObservingPairedDevices() async {
        observationTask?.cancel()

        #if canImport(WiFiAware)
        guard isSupported else {
            logger.warning("Cannot observe paired devices — Wi-Fi Aware not supported")
            return
        }

        observationTask = Task { [weak self] in
            guard let self else { return }
            do {
                for await devices in WAPairedDevice.allDevices() {
                    guard !Task.isCancelled else { break }
                    self.pairedDevices = devices
                    self.logger.debug("Paired devices updated: \(devices.count) device(s)")
                }
            } catch {
                self.logger.error("Paired device observation failed: \(error.localizedDescription)")
            }
        }
        #else
        pairedDevices = []
        logger.info("Wi-Fi Aware not available — paired device observation is a no-op")
        #endif
    }

    func stopObservingPairedDevices() {
        observationTask?.cancel()
        observationTask = nil
    }
}
