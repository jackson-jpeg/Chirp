import CoreLocation
import SwiftUI

/// The app's own consent to being shown on the map, asked every single time.
///
/// This is deliberately *not* a screen that leads to the system prompt. App
/// Review Guideline 5.1.2(i) asks for two separate things, and the build that
/// merged them into one sheet was rejected twice for it:
///
///   * iOS owns the permission. When it has never been asked, Check In fires
///     `requestWhenInUseAuthorization()` directly and the purpose string does
///     the explaining. Nothing of ours is drawn in front of it. (The previous
///     round's `LocationCheckInSheet` was exactly that screen, and is gone.)
///   * The app owns the sharing. Once iOS has said yes, *this* sheet asks
///     whether to actually go on the map, and it has to be refusable.
///
/// So both buttons are real answers and neither is a dead end. Share for 15
/// Minutes starts one session; Don't Share starts nothing and leaves the app
/// exactly as usable. Swiping the sheet away is a decline, not a deferral,
/// which is why `onDisappear` reports one when no button was pressed.
///
/// Nothing here is remembered. There is no "don't ask again", no default, and
/// no stored answer: a check-in is one tap of Check In plus one tap of Share,
/// every time, and a relaunch always begins checked out. See
/// ``LocationSharing`` and `LocationCheckInTests.testCheckInStateIsNeverPersisted`.
struct LocationConsentSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// `true` to share for one 15 minute session, `false` for every way of
    /// saying no: the Don't Share button and swipe-to-dismiss alike.
    var onDecision: (Bool) -> Void

    /// Guards against `onDisappear` reporting a second, contradicting answer
    /// after a button already reported one.
    @State private var answered = false
    @State private var showAbout = false

    private let amber = Constants.Colors.amber
    private let amberInk = Constants.Colors.amberInk

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(amberInk)
                    .padding(.top, 32)

                Text(String(localized: "location.consent.title"))
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Constants.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(String(localized: "location.consent.body"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Constants.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }

            Button {
                showAbout = true
            } label: {
                Text(String(localized: "location.about.link"))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(amberInk)
                    .underline()
            }
            .accessibilityIdentifier(AccessibilityID.locationAboutLink)
            .padding(.top, 18)

            Spacer(minLength: 24)

            // Both answers are the same shape and the same size. The decline
            // is not a footnote, a text link, or a corner X: 5.1.2(i) wants a
            // refusal that is as easy to find as the acceptance.
            VStack(spacing: 12) {
                Button {
                    answer(true)
                } label: {
                    Text(String(localized: "location.consent.share"))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Constants.Colors.onAmber)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: Constants.Layout.buttonCornerRadius)
                                .fill(amber)
                        )
                }
                .accessibilityIdentifier(AccessibilityID.locationShareButton)

                Button {
                    answer(false)
                } label: {
                    Text(String(localized: "location.consent.decline"))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Constants.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: Constants.Layout.buttonCornerRadius)
                                .fill(Constants.Colors.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Constants.Layout.buttonCornerRadius)
                                        .stroke(Constants.Colors.surfaceBorder, lineWidth: 1)
                                )
                        )
                }
                .accessibilityIdentifier(AccessibilityID.locationDontShareButton)
            }
        }
        .padding(.horizontal, Constants.Layout.horizontalPadding)
        .padding(.bottom, 28)
        .background(SkyBackdrop())
        .presentationDetents([.medium, .large])
        // Swipe-to-dismiss stays enabled on purpose: it is one of the ways to
        // say no, and `onDisappear` below turns it into one.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.locationConsentSheet)
        .demoBanner()
        .sheet(isPresented: $showAbout) {
            AboutLocationSharingView()
        }
        .onDisappear {
            guard !answered else { return }
            answered = true
            onDecision(false)
        }
    }

    private func answer(_ share: Bool) {
        guard !answered else { return }
        answered = true
        onDecision(share)
        dismiss()
    }
}

// MARK: - About

/// The four things worth knowing about location sharing, on a page of their
/// own rather than in front of a permission prompt.
///
/// These are the same four points the old pre-prompt explainer carried. They
/// are reference material, reachable from the consent sheet and from
/// Settings > Privacy, and they are not on the path to anything: opening this
/// grants nothing and starts nothing.
struct AboutLocationSharingView: View {
    @Environment(\.dismiss) private var dismiss

    private let amber = Constants.Colors.amber
    private let amberInk = Constants.Colors.amberInk

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    point(
                        icon: "hand.tap.fill",
                        title: String(localized: "location.point.manual.title"),
                        body: String(localized: "location.point.manual.body")
                    )
                    point(
                        icon: "timer",
                        title: String(localized: "location.point.expiry.title"),
                        body: String(localized: "location.point.expiry.body")
                    )
                    point(
                        icon: "antenna.radiowaves.left.and.right",
                        title: String(localized: "location.point.peers.title"),
                        body: String(localized: "location.point.peers.body")
                    )
                    point(
                        icon: "hand.raised.fill",
                        title: String(localized: "location.point.optional.title"),
                        body: String(localized: "location.point.optional.body")
                    )

                    Text(String(localized: "location.footnote"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Constants.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
                .padding(Constants.Layout.cardPadding)
            }
            .background(SkyBackdrop())
            .navigationTitle(String(localized: "location.about.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done")) { dismiss() }
                        .foregroundStyle(amberInk)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.locationAboutView)
    }

    private func point(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(amberInk)
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
    enum Outcome: Equatable {
        /// iOS has never been asked. The caller fires the system prompt with
        /// nothing drawn in front of it, then asks for consent if it is granted.
        case askSystemPermission
        /// iOS has already granted it. Straight to the app's own consent.
        case askConsent
        /// Declined, restricted, or Location Services off: the system prompt
        /// cannot appear again, so the caller shows the inline notice with
        /// Open Settings. Never a custom screen that leads back to a prompt.
        case showSettingsNotice
    }

    static func perform(_ sharing: LocationSharing) async -> Outcome {
        // `locationServicesEnabled()` does synchronous work Apple warns
        // against on the main thread.
        let servicesOn = await Task.detached { CLLocationManager.locationServicesEnabled() }.value
        switch sharing.routeForCheckIn(locationServicesEnabled: servicesOn) {
        case .checkInNow:
            return .askConsent
        case .explainThenAsk:
            return .askSystemPermission
        case .blocked:
            return .showSettingsNotice
        }
    }
}
