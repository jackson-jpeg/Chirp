import CoreLocation
import SwiftUI

/// The one place the app asks to put you on the map.
///
/// It exists so that permission is never requested as a side effect of
/// opening a screen: the user reads what sharing means, then chooses. Every
/// state has a way out that leaves the app fully working — the decline path
/// is a real path, not a dead end.
struct LocationCheckInSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private let amber = Constants.Colors.amber
    private let green = Constants.Colors.electricGreen

    private var sharing: LocationSharing { appState.locationSharing }

    /// Which of the four states the sheet is in.
    private enum Stage {
        /// Never asked — explain, then offer the system prompt.
        case explain
        /// Asked and declined — say what still works, offer Settings.
        case declined
        /// Allowed, not sharing — offer the check-in.
        case ready
        /// Checked in — show the countdown and a one-tap stop.
        case sharing
    }

    private var stage: Stage {
        if sharing.isSharing { return .sharing }
        if sharing.isDeclined { return .declined }
        if sharing.isAuthorized { return .ready }
        return .explain
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    switch stage {
                    case .explain:
                        explanationCard
                        explainActions
                    case .declined:
                        declinedCard
                        declinedActions
                    case .ready:
                        explanationCard
                        readyActions
                    case .sharing:
                        sharingCard
                        sharingActions
                    }

                    footnote
                }
                .padding(.horizontal, Constants.Layout.horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(
                LinearGradient(
                    colors: [Constants.Colors.backgroundPrimary, Constants.Colors.backgroundSecondary],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle(String(localized: "location.sheet.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) { dismiss() }
                        .foregroundStyle(amber)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: stage == .sharing ? "location.fill.viewfinder" : "mappin.and.ellipse")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(stage == .sharing ? green : amber)
                .padding(.top, 12)

            Text(headline)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(Constants.Colors.textPrimary)
                .multilineTextAlignment(.center)
        }
    }

    private var headline: String {
        switch stage {
        case .explain, .ready: String(localized: "location.headline.offer")
        case .declined: String(localized: "location.headline.declined")
        case .sharing: String(localized: "location.headline.sharing")
        }
    }

    // MARK: - Cards

    private var explanationCard: some View {
        card {
            VStack(alignment: .leading, spacing: 18) {
                bullet(
                    icon: "hand.tap.fill",
                    title: String(localized: "location.point.manual.title"),
                    body: String(localized: "location.point.manual.body")
                )
                bullet(
                    icon: "timer",
                    title: String(localized: "location.point.expiry.title"),
                    body: String(localized: "location.point.expiry.body")
                )
                bullet(
                    icon: "antenna.radiowaves.left.and.right",
                    title: String(localized: "location.point.peers.title"),
                    body: String(localized: "location.point.peers.body")
                )
                bullet(
                    icon: "hand.raised.fill",
                    title: String(localized: "location.point.optional.title"),
                    body: String(localized: "location.point.optional.body")
                )
            }
        }
    }

    private var declinedCard: some View {
        card {
            VStack(alignment: .leading, spacing: 18) {
                bullet(
                    icon: "checkmark.circle.fill",
                    tint: green,
                    title: String(localized: "location.declined.works.title"),
                    body: String(localized: "location.declined.works.body")
                )
                bullet(
                    icon: "map",
                    tint: green,
                    title: String(localized: "location.declined.map.title"),
                    body: String(localized: "location.declined.map.body")
                )
                bullet(
                    icon: "gear",
                    title: String(localized: "location.declined.change.title"),
                    body: String(localized: "location.declined.change.body")
                )
            }
        }
    }

    private var sharingCard: some View {
        card {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(green)
                        .frame(width: 10, height: 10)
                        .modifier(StatusPulsingDot())
                    Text(String(localized: "location.sharing.live"))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(green)
                }

                Text(sharing.remainingText)
                    .font(.system(size: 44, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Constants.Colors.textPrimary)
                    .monospacedDigit()
                    .accessibilityLabel(String(localized: "location.sharing.remainingA11y \(sharing.remainingText)"))

                Text(String(localized: "location.sharing.autostop"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Constants.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Actions

    private var explainActions: some View {
        VStack(spacing: 12) {
            primaryButton(String(localized: "location.action.continue"), tint: amber) {
                // The system prompt appears here and nowhere else. Granting it
                // still does not share anything — the user taps Check In next.
                sharing.requestPermission()
            }
            .accessibilityIdentifier(AccessibilityID.locationContinue)

            secondaryButton(String(localized: "location.action.notNow")) { dismiss() }
                .accessibilityIdentifier(AccessibilityID.locationNotNow)
        }
    }

    private var readyActions: some View {
        VStack(spacing: 12) {
            primaryButton(String(localized: "location.action.checkIn"), tint: green) {
                sharing.beginCheckIn()
                HapticsManager.shared.pttDown()
            }
            .accessibilityIdentifier(AccessibilityID.locationCheckIn)

            secondaryButton(String(localized: "location.action.notNow")) { dismiss() }
                .accessibilityIdentifier(AccessibilityID.locationNotNow)
        }
    }

    private var declinedActions: some View {
        VStack(spacing: 12) {
            primaryButton(String(localized: "location.action.openSettings"), tint: amber) {
                appState.openAppSettings()
            }

            secondaryButton(String(localized: "location.action.keepOff")) { dismiss() }
                .accessibilityIdentifier(AccessibilityID.locationNotNow)
        }
    }

    private var sharingActions: some View {
        VStack(spacing: 12) {
            primaryButton(String(localized: "location.action.stop"), tint: Constants.Colors.hotRed) {
                sharing.stopSharing(reason: .user)
                HapticsManager.shared.pttUp()
            }
            .accessibilityIdentifier(AccessibilityID.locationStopSharing)

            secondaryButton(String(localized: "common.done")) { dismiss() }
        }
    }

    // MARK: - Footnote

    private var footnote: some View {
        Text(String(localized: "location.footnote"))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Constants.Colors.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }

    // MARK: - Building blocks

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(Constants.Layout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                    .fill(Constants.Colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                            .stroke(Constants.Colors.surfaceBorder, lineWidth: 0.5)
                    )
            )
    }

    private func bullet(
        icon: String,
        tint: Color? = nil,
        title: String,
        body: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint ?? amber)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Constants.Colors.textPrimary)
                Text(body)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Constants.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func primaryButton(
        _ title: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: Constants.Layout.buttonCornerRadius)
                        .fill(tint)
                )
        }
    }

    private func secondaryButton(
        _ title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Constants.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: Constants.Layout.buttonCornerRadius)
                        .fill(Constants.Colors.surfaceGlass)
                )
        }
    }
}
