import SwiftUI

// MARK: - DEMO banner

/// The strip across the top of every screen while Demo Mode is on: says
/// plainly that the people on screen are simulated, and exits in one tap.
struct DemoBanner: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 10) {
            Text(String(localized: "demo.banner.badge"))
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Constants.Colors.amber))
                .accessibilityIdentifier(AccessibilityID.demoBadge)

            Text(String(localized: "demo.banner.caption"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Constants.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 8)

            Button {
                appState.demoMode.setEnabled(false)
                HapticsManager.shared.pttUp()
            } label: {
                Text(String(localized: "demo.banner.exit"))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Constants.Colors.amber)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().stroke(Constants.Colors.amber.opacity(0.6), lineWidth: 1))
            }
            .accessibilityIdentifier(AccessibilityID.demoExitButton)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(
            Constants.Colors.slate900
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Constants.Colors.amber.opacity(0.35)).frame(height: 1)
                }
                .ignoresSafeArea(edges: .top)
        )
        .accessibilityElement(children: .contain)
    }
}

private struct DemoBannerModifier: ViewModifier {
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if appState.demoMode.isActive {
                DemoBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: appState.demoMode.isActive)
    }
}

extension View {
    /// Pins the DEMO banner above this view while Demo Mode is on. Applied at
    /// the app root and on every sheet, which covers every screen.
    func demoBanner() -> some View { modifier(DemoBannerModifier()) }
}

// MARK: - Try Demo Mode

/// Shown on every screen that is empty because nobody is nearby.
struct TryDemoModeButton: View {
    @Environment(AppState.self) private var appState

    /// Include the one-line explanation under the button.
    var showsCaption = true

    var body: some View {
        VStack(spacing: 8) {
            Button {
                appState.demoMode.setEnabled(true)
                HapticsManager.shared.pttDown()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text(String(localized: "demo.try.button"))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(Capsule().fill(Constants.Colors.amber))
            }
            .accessibilityIdentifier(AccessibilityID.tryDemoModeButton)

            if showsCaption {
                Text(String(localized: "demo.try.caption"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Constants.Colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Permission notices

/// Inline notice for a permission the user declined. The feature that needs
/// it says so where it lives, with the one action that can change it; the
/// rest of the app is unaffected. Never a modal, never on launch.
struct PermissionNotice: View {
    enum Kind {
        case microphone
        case location
    }

    @Environment(AppState.self) private var appState
    let kind: Kind

    private var icon: String {
        switch kind {
        case .microphone: "mic.slash.fill"
        case .location: "location.slash.fill"
        }
    }

    private var title: String {
        switch kind {
        case .microphone: String(localized: "permission.mic.off.title")
        case .location: String(localized: "permission.location.off.title")
        }
    }

    private var message: String {
        switch kind {
        case .microphone: String(localized: "permission.mic.off.body")
        case .location: String(localized: "permission.location.off.body")
        }
    }

    private var identifier: String {
        switch kind {
        case .microphone: AccessibilityID.micDeniedNotice
        case .location: AccessibilityID.locationDeniedNotice
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Constants.Colors.amber)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Constants.Colors.textPrimary)
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Constants.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                appState.openAppSettings()
            } label: {
                Text(String(localized: "permission.openSettings"))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Constants.Colors.amber))
            }
            .accessibilityIdentifier(AccessibilityID.openSettingsButton)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius)
                .fill(Constants.Colors.slate900.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius)
                        .stroke(Constants.Colors.amber.opacity(0.35), lineWidth: 0.75)
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}
