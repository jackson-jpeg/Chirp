import SwiftUI

@main
struct ChirpApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isOnboardingComplete {
                    HomeView()
                } else {
                    OnboardingView()
                }
            }
            .demoBanner()
            .environment(appState)
            .preferredColorScheme(appearance.colorScheme)
            .task {
                await appState.start()
                #if DEBUG
                ScreenshotSeed.applyIfRequested(to: appState)
                #endif
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    // Read, never ask: the user may have changed it in
                    // Settings (from an Open Settings notice) and come back.
                    appState.refreshMicPermission()
                case .background, .inactive:
                    break
                @unknown default:
                    break
                }
            }
        }
    }
}
