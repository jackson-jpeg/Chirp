import ChirpCore
import CoreLocation
import SwiftUI

/// Nearby, built to `v2/design/Nearby.dc.html`: who can hear you and how your
/// voice gets to them, then sharing where you are and Ping.
/// Tap a person for Find and Block (App Review 5.1.2(i)); long press works too.
struct NearbyView: View {
    @Environment(Flock.self) private var flock
    @Environment(Router.self) private var router
    @Environment(Mesh.self) private var mesh
    @Environment(Transport.self) private var transport
    @Environment(CheckInLocation.self) private var checkIn
    @State private var chosen: NearbyEntry?
    @State private var toBlock: NearbyEntry?
    @State private var noFlock = false
    @State private var askPing = false
    @State private var pinged: Person?

    private var entries: [NearbyEntry] {
        flock.others
            .map(NearbyEntry.demo(for:))
            .map { e in
                // A friend's check-in: what it says replaces the fixture's.
                guard let c = mesh.checkIn(of: e.person) else { return e }
                var e = e
                e.checkedIn = true
                e.direction = nil
                e.distance = checkIn.here.map {
                    NearbyEntry.metres($0.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)))
                }
                return e
            }
    }

    var body: some View {
        let entries = self.entries
        ScrollView {
            VStack(spacing: 0) {
                header
                NearbyScene(you: flock.you, entries: entries)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: Color.hex(0x14233F, opacity: 0.06), radius: 0, y: 1)
                    .shadow(color: Theme.shadow, radius: 15, y: 10)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                people(entries)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                shareCard
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                pingCard(entries)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }
            .padding(.bottom, 16)
        }
        .screenBackground()
        .confirmationDialog(chosen?.person.name ?? "", isPresented: Binding(
            get: { chosen != nil }, set: { if !$0 { chosen = nil } }
        ), titleVisibility: .hidden, presenting: chosen) { e in
            Button("Find \(e.person.name)") { router.find(e.person) }
            Button("Block \(e.person.name)", role: .destructive) { toBlock = e }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Block \(toBlock?.person.name ?? "")?", isPresented: Binding(
            get: { toBlock != nil }, set: { if !$0 { toBlock = nil } }
        ), presenting: toBlock) { e in
            Button("Block", role: .destructive) { block(e) }
            Button("Cancel", role: .cancel) {}
        } message: { e in
            Text("You won't hear \(e.person.name), and \(e.person.name) won't hear you or see you here.")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Nearby")
                .font(.nunito(34, .black, relativeTo: .largeTitle))
                .tracking(-0.34)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Who can hear you, and how your voice gets there")
                .font(.meta)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        // The file's 56 pt top padding, less the 47 pt status bar inset of a 390 x 844 phone.
        .padding(.top, 9)
    }

    // MARK: People

    @ViewBuilder
    private func people(_ entries: [NearbyEntry]) -> some View {
        if entries.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Nobody nearby yet")
                    .font(.nunito(17, .black, relativeTo: .headline))
                    .foregroundStyle(Theme.ink)
                Text(flock.flockName.isEmpty
                     ? "When someone is close enough to hear you, they show up here."
                     : "When someone in \(flock.flockName) is close enough to hear you, they show up here.")
                    .font(.nunito(14, .bold, relativeTo: .subheadline))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !mesh.inDemo, let channel = mesh.flockChannel, let link = FlockInvite.link(for: channel) {
                    ShareLink(item: link,
                              subject: Text("Join \(channel.name) on ChirpChirps"),
                              message: Text("Join my flock on ChirpChirps, so we can talk with no signal. Open this link on your iPhone.")) {
                        Label("Invite friends", systemImage: "person.badge.plus")
                            .font(.nunito(15, .black, relativeTo: .subheadline))
                            .foregroundStyle(Theme.link)
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("nearby.invite")
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                    personRow(e)
                        .overlay(alignment: .bottom) {
                            if i < entries.count - 1 { Rectangle().fill(Theme.quiet).frame(height: 1) }
                        }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func personRow(_ e: NearbyEntry) -> some View {
        Button { chosen = e } label: {
            HStack(spacing: 14) {
                ChatWellAvatar(palette: e.person.palette, size: 48, origin: CGPoint(x: 22, y: 28), scale: 0.13)
                VStack(alignment: .leading, spacing: 1) {
                    Text(e.person.name)
                        .font(.nunito(17, .black, relativeTo: .headline))
                        .foregroundStyle(Theme.ink)
                    Text(e.statusText)
                        .font(.nunito(14, .bold, relativeTo: .subheadline))
                        .foregroundStyle(e.isDirect ? Theme.signalText : Theme.inkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if e.distance != nil || e.direction != nil {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let d = e.distance {
                            Text(d)
                                .font(.nunito(17, .black, relativeTo: .headline))
                                .foregroundStyle(Theme.ink)
                        }
                        if let dir = e.direction {
                            HStack(spacing: 4) {
                                ChatIcon.arrowUp
                                    .stroke(Theme.ink, style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
                                    .frame(width: 14, height: 14)
                                    .rotationEffect(.degrees(e.arrowDegrees))
                                Text(dir)
                            }
                            .font(.nunito(13, .heavy, relativeTo: .footnote))
                            .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Find \(e.person.name)", systemImage: "location.circle") { router.find(e.person) }
            Button("Block \(e.person.name)", systemImage: "hand.raised", role: .destructive) { toBlock = e }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(e.accessibilitySummary)
        .accessibilityHint("Shows Find and Block")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { chosen = e }
        .accessibilityAction(named: "Find \(e.person.name)") { router.find(e.person) }
        .accessibilityAction(named: "Block \(e.person.name)") { toBlock = e }
    }

    private func block(_ e: NearbyEntry) {
        withAnimation(.easeOut(duration: 0.25)) { flock.block(e.person.id) }
        if pinged == e.person { pinged = nil }
    }

    // MARK: Share and Ping

    /// Check-in: off until you tap Share, our own question every time, then
    /// iOS's (the first time only), 15 minutes, then off by itself.
    private var shareCard: some View {
        @Bindable var checkIn = checkIn
        return TimelineView(.periodic(from: .now, by: 15)) { context in
            let left = checkIn.minutesLeft(at: context.date)
            NearbyActionCard(
                icon: NearbyIcons.pin,
                title: "Share where you are",
                subtitle: left.map { "On · \($0) min left" } ?? "Off · asks every time",
                button: left == nil ? "Share" : "Stop",
                filled: true
            ) {
                if left != nil { checkIn.stop() }
                else if mesh.canCheckIn { checkIn.tapShare() }
                else { noFlock = true }
            }
        }
        .alert("Share where you are with \(flock.displayName)?", isPresented: $checkIn.askingConsent) {
            Button("Share for 15 minutes") {
                // The radio carries it; this tap is the one that needs other phones.
                transport.start()
                checkIn.answer(yes: true)
            }
            Button("Not now", role: .cancel) { checkIn.answer(yes: false) }
        } message: {
            Text("Only your flock sees it. It stops after 15 minutes, when you tap Stop, or when you leave the app. You're asked every time.")
        }
        .alert("Location is off for ChirpChirps", isPresented: $checkIn.showDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("To share where you are, allow location While Using the App in Settings. Everything else works without it.")
        }
        .alert("Share with a locked flock", isPresented: $noFlock) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Where you are only goes to a locked flock you're in, never to everyone nearby.")
        }
    }

    private func pingCard(_ entries: [NearbyEntry]) -> some View {
        NearbyActionCard(
            icon: NearbyIcons.bell,
            title: "Lost someone?",
            subtitle: pinged.map { "Chirping on \($0.name)'s phone now" } ?? "Plays a loud chirp on their phone",
            button: "Ping",
            filled: false
        ) {
            askPing = true
        }
        .disabled(entries.isEmpty)
        .confirmationDialog("Who should hear the chirp?", isPresented: $askPing, titleVisibility: .visible) {
            ForEach(entries) { e in
                Button(e.person.name) { ping(e.person) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func ping(_ p: Person) {
        pinged = p
        Task {
            try? await Task.sleep(for: .seconds(4))
            if pinged == p { pinged = nil }
        }
    }
}

// MARK: - Action card

/// "Share where you are" and "Lost someone?": icon, two lines, a pill button.
struct NearbyActionCard: View {
    var icon: ChatIcon
    var title: String
    var subtitle: String
    var button: String
    var filled: Bool
    var action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            icon
                .stroke(Theme.ink, style: StrokeStyle(lineWidth: 2.2 * 28 / 24, lineCap: .round, lineJoin: .round))
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.nunito(16, .black, relativeTo: .headline))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.nunito(14, .bold, relativeTo: .subheadline))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button(action: action) {
                Text(button)
                    .font(.nunito(15, .black, relativeTo: .subheadline))
                    .foregroundStyle(filled ? Theme.onSolid : Theme.ink)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(filled ? Theme.solid : Theme.card, in: Capsule())
                    .overlay {
                        if !filled { Capsule().strokeBorder(Theme.solid, lineWidth: 2) }
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// The file's 24-unit icons for the two cards.
@MainActor
enum NearbyIcons {
    /// `circle 12 10 r3` and `M12 21s7-6 7-11a7 7 0 0 0-14 0c0 5 7 11 7 11z`.
    static let pin = ChatIcon { p in
        p.addEllipse(in: CGRect(x: 9, y: 7, width: 6, height: 6))
        p.move(to: CGPoint(x: 12, y: 21))
        p.addCurve(to: CGPoint(x: 19, y: 10), control1: CGPoint(x: 12, y: 21), control2: CGPoint(x: 19, y: 15))
        p.addCurve(to: CGPoint(x: 12, y: 3), control1: CGPoint(x: 19, y: 6.13), control2: CGPoint(x: 15.87, y: 3))
        p.addCurve(to: CGPoint(x: 5, y: 10), control1: CGPoint(x: 8.13, y: 3), control2: CGPoint(x: 5, y: 6.13))
        p.addCurve(to: CGPoint(x: 12, y: 21), control1: CGPoint(x: 5, y: 15), control2: CGPoint(x: 12, y: 21))
        p.closeSubpath()
    }

    /// `M6 8a6 6 0 0 1 12 0c0 7 3 8 3 8H3s3-1 3-8M10 20a2 2 0 0 0 4 0`.
    static let bell = ChatIcon { p in
        p.move(to: CGPoint(x: 6, y: 8))
        p.addCurve(to: CGPoint(x: 12, y: 2), control1: CGPoint(x: 6, y: 4.69), control2: CGPoint(x: 8.69, y: 2))
        p.addCurve(to: CGPoint(x: 18, y: 8), control1: CGPoint(x: 15.31, y: 2), control2: CGPoint(x: 18, y: 4.69))
        p.addCurve(to: CGPoint(x: 21, y: 16), control1: CGPoint(x: 18, y: 15), control2: CGPoint(x: 21, y: 16))
        p.addLine(to: CGPoint(x: 3, y: 16))
        p.addCurve(to: CGPoint(x: 6, y: 8), control1: CGPoint(x: 3, y: 16), control2: CGPoint(x: 6, y: 15))
        p.move(to: CGPoint(x: 10, y: 20))
        p.addCurve(to: CGPoint(x: 12, y: 22), control1: CGPoint(x: 10, y: 21.1), control2: CGPoint(x: 10.9, y: 22))
        p.addCurve(to: CGPoint(x: 14, y: 20), control1: CGPoint(x: 13.1, y: 22), control2: CGPoint(x: 14, y: 21.1))
    }
}

// MARK: - The scene

/// The sky card from the file: you and each person on the wire, a solid wire
/// to everyone you reach directly, a dotted one beyond, and the two chips
/// "Direct" and "Through Jon" over it. Drawn in the file's 358 x 150 space.
struct NearbyScene: View {
    var you: Person
    var entries: [NearbyEntry]

    private static let size = CGSize(width: 358, height: 150)

    var body: some View {
        let placed = entries.filter { $0.sceneCenter != nil }
        let hasRelay = placed.contains { !$0.isDirect }
        Canvas { ctx, size in
            let k = size.width / Self.size.width
            ctx.scaleBy(x: k, y: k)
            ctx.fill(Path(CGRect(origin: .zero, size: Self.size)), with: .linearGradient(
                Gradient(stops: [.init(color: Theme.sceneTop, location: 0), .init(color: Theme.sceneMid, location: 0.7),
                                 .init(color: Theme.sceneBottom, location: 1)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: Self.size.height)))

            var wire = Path()
            wire.move(to: CGPoint(x: 14, y: 96))
            wire.addQuadCurve(to: CGPoint(x: 205, y: 98), control: CGPoint(x: 110, y: 116))
            ctx.stroke(wire, with: .color(Theme.wire), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            if hasRelay {
                var far = Path()
                far.move(to: CGPoint(x: 205, y: 98))
                far.addQuadCurve(to: CGPoint(x: 344, y: 92), control: CGPoint(x: 270, y: 112))
                ctx.stroke(far, with: .color(Theme.wire), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 8]))
            }

            BirdRenderer.draw(&ctx, palette: you.palette, beakOpen: false, center: CGPoint(x: 40, y: 79), scale: 0.17)
            Self.label(&ctx, "You", x: 40, baseline: 132)
            for e in placed {
                guard let c = e.sceneCenter else { continue }
                BirdRenderer.draw(&ctx, palette: e.person.palette, beakOpen: false, center: c, scale: 0.17, facingLeft: true)
                Self.label(&ctx, e.person.name, x: c.x, baseline: e.labelBaseline)
            }

            if placed.contains(where: \.isDirect) {
                Self.chip(&ctx, CGRect(x: 88, y: 16, width: 74, height: 24), "Direct", Theme.signalText)
                var line = Path()
                line.move(to: CGPoint(x: 14, y: 46)); line.addLine(to: CGPoint(x: 198, y: 46))
                ctx.stroke(line, with: .color(Theme.signalText.opacity(0.5)), lineWidth: 2)
            }
            if hasRelay, let relay = placed.first(where: { !$0.isDirect }), case .through(let via) = relay.route {
                Self.chip(&ctx, CGRect(x: 216, y: 16, width: 100, height: 24), "Through \(via.name)", Theme.inkSecondary)
                var line = Path()
                line.move(to: CGPoint(x: 206, y: 46)); line.addLine(to: CGPoint(x: 344, y: 46))
                ctx.stroke(line, with: .color(Theme.inkSecondary.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 2, dash: [3, 5]))
            }
        }
        .aspectRatio(Self.size.width / Self.size.height, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isImage)
    }

    nonisolated private static func label(_ ctx: inout GraphicsContext, _ text: String, x: CGFloat, baseline: CGFloat) {
        ctx.draw(Text(text).font(.custom("Nunito", fixedSize: 12).weight(.black)).foregroundStyle(Theme.ink),
                 at: CGPoint(x: x, y: baseline - 4), anchor: .center)
    }

    nonisolated private static func chip(_ ctx: inout GraphicsContext, _ r: CGRect, _ text: String, _ color: Color) {
        ctx.fill(Path(roundedRect: r, cornerRadius: 12), with: .color(Theme.chipOnScene))
        ctx.draw(Text(text).font(.custom("Nunito", fixedSize: 12).weight(.black)).foregroundStyle(color),
                 at: CGPoint(x: r.midX, y: r.midY), anchor: .center)
    }

    /// "Your voice goes straight to Maya and Jon. It reaches Priya through Jon's phone."
    private var accessibilityText: String {
        let direct = entries.filter(\.isDirect).map(\.person)
        var parts: [String] = []
        if !direct.isEmpty { parts.append("Your voice goes straight to \(TalkText.list(direct.map(\.name))).") }
        for e in entries {
            if case .through(let via) = e.route {
                parts.append("It reaches \(e.person.name) through \(via.name)'s phone.")
            }
        }
        return parts.isEmpty ? "Nobody can hear you right now." : parts.joined(separator: " ")
    }
}
