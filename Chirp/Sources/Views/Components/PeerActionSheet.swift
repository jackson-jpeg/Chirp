import SwiftUI

/// Who a block or report is about, resolved to the identity that actually
/// enforces.
///
/// This type exists because the app has three different notions of "who a peer
/// is" and only one of them works. `ChirpPeer.id` is the MultipeerConnectivity
/// display name, which is the callsign the peer chose; `MeshRouter` filters on
/// the routing UUID stamped on every packet; and the identity keypair produces
/// a fingerprint that survives both. Blocking a peer by callsign produced a
/// `BlockList` entry that `MeshRouter.setBlockedOrigins` discarded outright
/// (it keeps only values that parse as a UUID), so the peer appeared in
/// Settings as blocked while their traffic kept arriving.
///
/// Every block and report call site now builds one of these first, so a block
/// is impossible to record against an identity that cannot be enforced.
struct PeerActionTarget: Identifiable, Equatable {
    /// The routing UUID, which is what enforcement keys on.
    let id: String
    /// The name to show. Display only: never an identity.
    let name: String
    /// The peer's identity fingerprint, when one has been verified from their
    /// beacon. Carried into a report so the reported device is identifiable,
    /// and used to re-key the block if the peer returns under a new routing
    /// UUID. `nil` when we have not yet verified one.
    let fingerprint: String?

    init(id: String, name: String, fingerprint: String? = nil) {
        self.id = id
        self.name = name
        self.fingerprint = fingerprint
    }

    /// Whether this target can actually be enforced. A target that fails this
    /// must not be offered a Block button, because the block would be a lie.
    var isEnforceable: Bool { UUID(uuidString: id) != nil }
}

/// Why a peer is being reported. Apple asks for a reason picker on a report;
/// this is also what makes the emailed report useful to a human.
enum ReportReason: String, CaseIterable, Identifiable {
    case harassment
    case sexualContent
    case threat
    case impersonation
    case spam
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .harassment: return String(localized: "report.reason.harassment")
        case .sexualContent: return String(localized: "report.reason.sexualContent")
        case .threat: return String(localized: "report.reason.threat")
        case .impersonation: return String(localized: "report.reason.impersonation")
        case .spam: return String(localized: "report.reason.spam")
        case .other: return String(localized: "report.reason.other")
        }
    }
}

/// The one sheet every Block and Report goes through.
///
/// Before this existed each screen rolled its own context menu, which is why
/// some screens had no way to block at all: the map pin and the message bubble
/// had one, the friends list had a broken one, and the voice-message inbox,
/// the talk-screen peer bubbles and the participant strip had none. App Review
/// Guideline 1.2 wants blocking reachable from everywhere a person appears, so
/// there is now one component and every surface presents it.
struct PeerActionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let target: PeerActionTarget
    /// The message this was opened from, when it was opened from one. Its text
    /// is offered to the report so the reviewer of the report can see what
    /// was actually said.
    var message: MeshTextMessage?

    var onBlock: (PeerActionTarget) -> Void
    var onReport: (PeerActionTarget, ReportReason, Bool) -> Void

    @State private var showBlockConfirm = false
    @State private var showReport = false
    @State private var reason: ReportReason = .harassment
    @State private var includeMessage = true

    private let red = Constants.Colors.hotRed

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                VStack(spacing: 12) {
                    Button {
                        showBlockConfirm = true
                    } label: {
                        actionLabel(
                            icon: "hand.raised.fill",
                            title: String(localized: "moderation.blockUser"),
                            subtitle: String(localized: "moderation.blockUser.detail"),
                            tint: red
                        )
                    }
                    .accessibilityIdentifier(AccessibilityID.peerSheetBlockButton)

                    Button {
                        showReport = true
                    } label: {
                        actionLabel(
                            icon: "flag.fill",
                            title: String(localized: "moderation.reportUser"),
                            subtitle: String(localized: "moderation.reportUser.detail"),
                            tint: Constants.Colors.amberInk
                        )
                    }
                    .accessibilityIdentifier(AccessibilityID.peerSheetReportButton)
                }
                .padding(.horizontal, Constants.Layout.horizontalPadding)
                .padding(.top, 20)

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(SkyBackdrop())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                        .foregroundStyle(Constants.Colors.textSecondary)
                }
            }
        }
        .presentationDetents([.height(340), .large])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.peerActionSheet)
        // One confirmation, as the guideline asks. Blocking is reversible from
        // Settings > Blocked Users, so a second one would be nagging.
        .confirmationDialog(
            String(localized: "moderation.blockConfirm.title \(target.name)"),
            isPresented: $showBlockConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "moderation.blockConfirm.action"), role: .destructive) {
                onBlock(target)
                dismiss()
            }
            .accessibilityIdentifier(AccessibilityID.peerSheetBlockConfirm)
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "moderation.blockConfirm.message"))
        }
        .sheet(isPresented: $showReport) {
            reportSheet
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            // A plain initial rather than `PeerAvatarView`, which needs a live
            // `ChirpPeer`. This sheet is opened from places where the peer is
            // only a stored identity, such as a message sender who has since
            // gone offline, and it must work there too.
            ZStack {
                Circle()
                    .fill(Constants.Colors.cardBackground)
                    .frame(width: 56, height: 56)
                Text(target.name.prefix(1).uppercased())
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Constants.Colors.textPrimary)
            }
            .padding(.top, 8)
            Text(target.name)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Constants.Colors.textPrimary)
            // The fingerprint is shown, not hidden, so the person blocking can
            // see that they are acting on a device identity rather than on a
            // name anyone could copy.
            if let fingerprint = target.fingerprint {
                Text(fingerprint)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Constants.Colors.textTertiary)
            }
        }
        .padding(.bottom, 4)
    }

    private var reportSheet: some View {
        NavigationStack {
            Form {
                Section(String(localized: "report.reason.title")) {
                    Picker(String(localized: "report.reason.title"), selection: $reason) {
                        ForEach(ReportReason.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityIdentifier(AccessibilityID.reportReasonPicker)
                }

                if message != nil {
                    Section {
                        Toggle(String(localized: "report.includeMessage"), isOn: $includeMessage)
                    }
                }

                Section {
                    Text(String(localized: "report.explanation"))
                        .font(.system(size: 13))
                        .foregroundStyle(Constants.Colors.textSecondary)
                }
            }
            .navigationTitle(String(localized: "moderation.reportUser"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { showReport = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "report.send")) {
                        // Reporting blocks too. Someone worth reporting is
                        // someone the reporter should stop hearing from, and
                        // making them do it twice is a way to be harassed
                        // while filling in a form.
                        onReport(target, reason, includeMessage && message != nil)
                        showReport = false
                        dismiss()
                    }
                    .accessibilityIdentifier(AccessibilityID.reportSendButton)
                }
            }
        }
    }

    private func actionLabel(icon: String, title: String, subtitle: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Constants.Colors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Constants.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
        }
        .padding(Constants.Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                .fill(Constants.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                        .stroke(tint.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

// MARK: - Resolving a target

extension AppState {

    /// Build a block/report target from a peer already known by routing UUID
    /// (a map pin, a message sender). Picks up the verified fingerprint if
    /// the beacon has one, so the block can follow them through a reinstall.
    func peerActionTarget(routingID: String, name: String) -> PeerActionTarget {
        PeerActionTarget(
            id: routingID,
            name: name,
            fingerprint: meshBeacon.identity(forRoutingID: routingID)?.fingerprint
        )
    }

    /// Build a target from a peer known only by the name they are using.
    ///
    /// This is the path that used to be broken. `ChirpPeer.id` and
    /// `ChirpFriend.id` are the MultipeerConnectivity display name or a
    /// pasted fingerprint, neither of which the router enforces on, so a
    /// block recorded from a peer list silently did nothing. The beacon is
    /// asked for the routing UUID that name currently belongs to.
    ///
    /// Returns nil when no beacon from that name has been heard, in which
    /// case there is nothing to block yet and the caller must say so rather
    /// than record a block that will not hold.
    func peerActionTarget(peerNamed name: String) -> PeerActionTarget? {
        guard let identity = meshBeacon.identity(forPeerNamed: name) else { return nil }
        return PeerActionTarget(
            id: identity.routingID,
            name: name,
            fingerprint: identity.fingerprint
        )
    }

    /// Record a block. Everything downstream (router, text service, beacon,
    /// Demo Mode) re-arms from `BlockList.onChange`.
    func applyBlock(_ target: PeerActionTarget) {
        blockList.block(id: target.id, name: target.name, fingerprint: target.fingerprint)
        HapticsManager.shared.denied()
    }

    /// File a report. Reporting blocks too: someone worth reporting is
    /// someone the reporter should stop hearing from immediately.
    func applyReport(
        _ target: PeerActionTarget,
        reason: ReportReason,
        message: MeshTextMessage?,
        includeMessageText: Bool
    ) {
        applyBlock(target)
        ReportService.fileReport(
            peerID: target.id,
            peerName: target.name,
            fingerprint: target.fingerprint,
            reason: reason,
            message: message,
            includeMessageText: includeMessageText,
            reporterPeerID: localPeerID
        )
    }
}
