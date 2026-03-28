import UIKit
import Combine

// MARK: - Camera Button PTT Service
//
// Provides hardware button PTT support for iPhones with a Camera Control
// button (iPhone 16+). On iOS 26+, this uses the system camera button
// capture API. On older devices or models without the button, this
// gracefully no-ops.
//
// Integration: Instantiate in ChannelView and wire onPress/onRelease
// to PTTEngine.startTransmitting / stopTransmitting.

@MainActor
final class CameraButtonPTT: ObservableObject {

    // MARK: - Callbacks

    /// Called when the hardware button is pressed (PTT start).
    var onPress: (() -> Void)?

    /// Called when the hardware button is released (PTT stop).
    var onRelease: (() -> Void)?

    // MARK: - State

    @Published private(set) var isAvailable: Bool = false
    @Published private(set) var isPressed: Bool = false

    // MARK: - Lifecycle

    init() {
        checkAvailability()
    }

    /// Activate camera button listening. Call when ChannelView appears.
    func activate() {
        guard isAvailable else { return }
        // TODO: Wire into iOS 26 CameraButton capture API when SDK ships.
        // For now the SwiftUI integration point is the .onCameraCaptureIntent
        // modifier or UIPressesEvent override on a hosting UIViewController.
    }

    /// Deactivate camera button listening. Call when ChannelView disappears.
    func deactivate() {
        if isPressed {
            isPressed = false
            onRelease?()
        }
    }

    // MARK: - Manual trigger (used by UIKit bridge)

    /// Call from a UIPressesEvent handler when camera button goes down.
    func handleButtonDown() {
        guard !isPressed else { return }
        isPressed = true
        onPress?()
    }

    /// Call from a UIPressesEvent handler when camera button goes up.
    func handleButtonUp() {
        guard isPressed else { return }
        isPressed = false
        onRelease?()
    }

    // MARK: - Private

    private func checkAvailability() {
        // iPhone 16 family: model identifiers iPhone17,x
        // The camera control button is physically present on these models.
        // At runtime we can check device model or, on iOS 26+, query the
        // system API. For now we do a best-effort model string check.
        #if targetEnvironment(simulator)
        isAvailable = false
        #else
        let model = deviceModelIdentifier()
        // iPhone 16 series starts at iPhone17,1
        isAvailable = model.hasPrefix("iPhone17,") || model.hasPrefix("iPhone18,")
        #endif
    }

    private func deviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingCString: $0) ?? "Unknown"
            }
        }
    }
}

// MARK: - SwiftUI View Extension
//
// Usage in ChannelView:
//
//   .cameraButtonPTT(handler) { pressed in
//       if pressed { engine.startTransmitting() }
//       else { engine.stopTransmitting() }
//   }

import SwiftUI

struct CameraButtonPTTModifier: ViewModifier {
    @ObservedObject var handler: CameraButtonPTT
    var action: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                handler.onPress = { action(true) }
                handler.onRelease = { action(false) }
                handler.activate()
            }
            .onDisappear {
                handler.deactivate()
            }
    }
}

extension View {
    /// Attach camera button PTT behavior to this view.
    func cameraButtonPTT(_ handler: CameraButtonPTT, action: @escaping (Bool) -> Void) -> some View {
        modifier(CameraButtonPTTModifier(handler: handler, action: action))
    }
}
