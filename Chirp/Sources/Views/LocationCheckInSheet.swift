import CoreLocation
import SwiftUI

/// The explanation shown before the system location prompt, and nothing else.
///
/// It appears only when the user has tapped Check In and iOS has never been
/// asked. Its one button, Continue, shows the system prompt; the prompt's own
/// "Don't Allow" is the way out. There is no Not Now, no Done, no close
/// button, and it cannot be swiped away (App Review Guideline 5.1.1(iv): a
/// message before a permission request may only lead to the request).
///
/// When the prompt is answered the sheet closes itself. Allowing completes the
/// check-in the user asked for; declining leaves the app exactly as usable as
/// before, and the Map tab then shows an inline notice with Open Settings.
///
/// Every other Check In case never shows this sheet: already authorized means
/// the tap is the check-in, and declined means the prompt can no longer
/// appear, so the Map shows the Settings notice instead. See
/// ``LocationSharing/routeForCheckIn(locationServicesEnabled:)``.
struct LocationCheckInSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    /// Called after the prompt is answered, with whether a check-in began.
    var onFinished: (Bool) -> Void = { _ in }

    @State private var hasAsked = false

    private let amber = Constants.Colors.amber
    private var sharing: LocationSharing { appState.locationSharing }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(amber)
                        .padding(.top, 28)

                    Text(String(localized: "location.headline.offer"))
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Constants.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                }

                explanationCard

                Button {
                    // The system prompt appears here and nowhere else.
                    hasAsked = true
                    sharing.requestPermission()
                } label: {
                    Text(String(localized: "location.action.continue"))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: Constants.Layout.buttonCornerRadius)
                                .fill(amber)
                        )
                }
                .disabled(hasAsked)
                .accessibilityIdentifier(AccessibilityID.locationContinue)

                Text(String(localized: "location.footnote"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Constants.Colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, Constants.Layout.horizontalPadding)
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
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(true)
        // children: .contain keeps the controls inside this screen
        // addressable: a bare identifier on a container is handed down
        // to every element in it, overwriting theirs.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.locationExplainer)
        .demoBanner()
        .onChange(of: sharing.authorizationStatus) { _, status in
            guard hasAsked, status != .notDetermined else { return }
            finish()
        }
        .onChange(of: scenePhase) { _, phase in
            // The system alert makes the app inactive; coming back active with
            // the status still undetermined means iOS showed no prompt (for
            // example, Location Services is switched off system-wide). Close
            // rather than leave a sheet with nothing left to do.
            guard hasAsked, phase == .active else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                if sharing.authorizationStatus == .notDetermined { finish() }
            }
        }
    }

    private func finish() {
        // Allowing answers the Check In the user already tapped.
        let checkedIn = sharing.isAuthorized && sharing.beginCheckIn()
        if checkedIn { HapticsManager.shared.pttDown() }
        onFinished(checkedIn)
        dismiss()
    }

    private var explanationCard: some View {
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

    private func bullet(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(amber)
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
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Check In

/// One place that decides what a Check In tap does, shared by the Map tab and
/// the chat location action so the two can never drift apart.
@MainActor
enum CheckInAction {
    enum Outcome {
        case checkedIn
        case showExplainer
        case showSettingsNotice
    }

    static func perform(_ sharing: LocationSharing) async -> Outcome {
        // `locationServicesEnabled()` does synchronous work Apple warns
        // against on the main thread.
        let servicesOn = await Task.detached { CLLocationManager.locationServicesEnabled() }.value
        switch sharing.routeForCheckIn(locationServicesEnabled: servicesOn) {
        case .checkInNow:
            sharing.beginCheckIn()
            return .checkedIn
        case .explainThenAsk:
            return .showExplainer
        case .blocked:
            return .showSettingsNotice
        }
    }
}
