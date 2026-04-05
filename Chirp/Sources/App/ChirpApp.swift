import SwiftUI

@main
struct ChirpApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isOnboardingComplete {
                    HomeView()
                } else {
                    OnboardingView()
                }
            }
            .environment(appState)
            .preferredColorScheme(.dark)
            .task {
                await appState.start()
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    if appState.isOnboardingComplete {
                        Task { await appState.requestMicPermission() }
                    }
                    appState.backgroundService.enterForeground()
                case .background:
                    appState.backgroundService.enterBackground()
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
        }
    }
}
