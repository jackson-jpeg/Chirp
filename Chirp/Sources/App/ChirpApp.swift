import SwiftUI

@main
struct ChirpApp: App {
    @State private var appState = AppState()
    @State private var navigateToChannel = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isOnboardingComplete {
                    NavigationStack {
                        HomeView()
                            .navigationDestination(isPresented: $navigateToChannel) {
                                if let channel = appState.channelManager.activeChannel {
                                    ChannelView(channel: channel)
                                }
                            }
                    }
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
                if newPhase == .active {
                    Task { await appState.requestMicPermission() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .chirpPTTShortcutTriggered)) { _ in
                // Action Button / Shortcut triggered — navigate to active channel
                if appState.channelManager.activeChannel != nil {
                    navigateToChannel = true
                }
            }
        }
    }
}
