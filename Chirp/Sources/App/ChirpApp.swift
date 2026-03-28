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
                case .background:
                    // Audio background mode keeps the app alive when
                    // AVAudioSession is active (recording or playing).
                    // The engine stays running if we're in a channel.
                    break
                case .active:
                    // Re-check mic permission when returning to foreground
                    // (user may have toggled it in Settings)
                    Task {
                        await appState.requestMicPermission()
                    }
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
        }
    }
}
