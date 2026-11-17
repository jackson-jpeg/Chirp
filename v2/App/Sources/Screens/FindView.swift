import SwiftUI
import ChirpCore

/// What Find can honestly show about one friend. With a precision fix it
/// points; without one it says only what the line knows (ChirpCore `Find.Fallback`).
enum FindState: Equatable {
    /// A precision fix: metres away, and the bearing in degrees from straight
    /// ahead (positive is to your right), nil while the direction is unknown.
    case pointing(meters: Int, bearing: Double?)
    case fallback(ChirpCore.Find.Fallback)
}

/// Find: "Finding Maya", the big arrow, the distance and Ping. Built to
/// `v2/design/Find.dc.html`.
struct FindView: View {
    @Environment(Router.self) private var router
    @Environment(Flock.self) private var flock
    @Environment(Mesh.self) private var mesh
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @State private var pinging = false
    /// Sends nowhere until `mesh.attach` points it at this friend.
    @State private var ranging = FindRanging()

    /// The friend being found; nil on screenshot runs and in Demo Mode.
    private var person: Person? {
        router.screenshotRun ? nil : router.findTarget.flatMap { flock.person($0) }
    }

    private var target: (name: String, palette: BirdPalette, pronoun: String) {
        guard let person else { return FindDemo.target }
        return (person.name, person.palette, "their")
    }

    private var status: String {
        guard let person else { return FindDemo.status }
        let asking = ranging.requested || person.peer.map { mesh.lookingForYou.contains($0) } == true
        return asking ? "\(person.name) is looking for you" : "Works best when \(person.name) opens Find too"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 9)

            GeometryReader { geo in
                ScrollView {
                    center
                        .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            buttons
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
        }
        .foregroundStyle(Theme.findInk)
        .background(Theme.findBackground.ignoresSafeArea())
        // Opening Find is the tap that brings up the Nearby Interaction prompt.
        .onAppear {
            guard !router.screenshotRun else { return }
            if let peer = person?.peer { mesh.attach(ranging, to: peer) }
            ranging.open()
        }
        .onDisappear {
            ranging.close()   // sends the stop before the mesh lets go
            mesh.detach(ranging)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { ranging.close() } else if phase == .active, !router.screenshotRun { ranging.open() }
        }
    }

    /// The design's content on screenshot runs; otherwise the fix, or what the
    /// line knows.
    private var state: FindState {
        if router.screenshotRun { return FindDemo.state }
        if let fix = ranging.fix { return .pointing(meters: fix.meters, bearing: fix.bearing) }
        return .fallback(mesh.fallback(for: person?.peer))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            CoverBirdDisc(palette: target.palette, diameter: 44,
                          center: CGPoint(x: 19, y: 27), scale: 0.13, well: Theme.card)
            VStack(alignment: .leading, spacing: 0) {
                Text("Finding \(target.name)")
                    .font(.nunito(20, .black, relativeTo: .title3))
                Text(status)
                    .font(.nunito(14, .heavy, relativeTo: .subheadline))
                    .foregroundStyle(Theme.findSecondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            CoverCloseButton(label: "Stop finding", tint: Theme.findInk) { router.overlay = nil }
        }
    }

    // MARK: Dial and words

    private var center: some View {
        VStack(spacing: 18) {
            dial
            words
        }
        .padding(.vertical, 44)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
    }

    private var dial: some View {
        ZStack {
            // Dark mode's card is navy on dark gold: the light-mode opacities vanish there.
            Circle().fill(Theme.card.opacity(scheme == .dark ? 0.45 : 0.18)).frame(width: 348, height: 348)
            Circle().fill(Theme.card.opacity(scheme == .dark ? 0.7 : 0.35)).frame(width: 304, height: 304)
            Circle().fill(Theme.card).frame(width: 268, height: 268)
            switch state {
            case .pointing(_, nil):
                fallbackMark(.inRange)
            case .pointing(_, let bearing?):
                FindArrow()
                    .fill(Theme.ink)
                    .frame(width: 170, height: 170)
                    .rotationEffect(.degrees(bearing))
                    .animation(.easeOut(duration: 0.25), value: bearing)
            case .fallback(let fallback):
                fallbackMark(fallback)
            }
        }
        .frame(width: 268, height: 268)
    }

    /// No arrow without a precision fix: their bird, faded when not heard.
    private func fallbackMark(_ fallback: ChirpCore.Find.Fallback) -> some View {
        let faded: Bool
        switch fallback {
        case .inRange: faded = false
        case .throughOthers: faded = false
        case .outOfRange: faded = true
        }
        return BirdView(palette: target.palette)
            .frame(width: 150, height: 122)
            .opacity(faded ? 0.45 : 1)
    }

    private var words: some View {
        VStack(spacing: 2) {
            switch state {
            case .pointing(let meters, let bearing):
                Text("\(meters) m")
                    .font(.nunito(84, .black, relativeTo: .largeTitle))
                    .lineHeight(.multiple(factor: 1))   // the design's line-height
                    .tracking(-1.68)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(bearing.map(FindWords.direction) ?? "Hold your phone up and turn slowly")
                    .font(.nunito(22, .black, relativeTo: .title2))
            case .fallback(let fallback):
                Text(FindWords.headline(fallback))
                    .font(.nunito(44, .black, relativeTo: .largeTitle))
                    .tracking(-0.88)
                Text(FindWords.line(fallback, name: target.name))
                    .font(.nunito(22, .black, relativeTo: .title2))
            }
            Text(hint)
                .font(.nunito(15, .heavy, relativeTo: .subheadline))
                .foregroundStyle(Theme.findSecondary)
                .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var hint: String {
        switch state {
        case .pointing: return "Your phone taps faster as you get closer"
        case .fallback(let f): return FindWords.hint(f, pronoun: target.pronoun)
        }
    }

    private var spokenSummary: String {
        switch state {
        case .pointing(let meters, let bearing):
            return "\(target.name), \(meters) \(meters == 1 ? "meter" : "meters"), \(bearing.map(FindWords.spokenDirection) ?? "direction not known yet, turn slowly")"
        case .fallback(let f):
            return "\(target.name), \(FindWords.headline(f)). \(FindWords.line(f, name: target.name))"
        }
    }

    // MARK: Buttons

    private var canPing: Bool {
        if case .fallback(.outOfRange) = state { return false }
        return true
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button {
                // A ping on the whisper channel (friends only, rate limited by
                // the receiver). Nothing answers it yet, so the label resets
                // after a few seconds.
                if let peer = person?.peer {
                    mesh.send { try $0.toFriend(.ping, Data(), peer: peer, now: .now) }
                }
                pinging = true
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    pinging = false
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: pinging ? "bell.and.waves.left.and.right" : "bell")
                        .font(.system(size: 18, weight: .bold))
                    Text(pinging ? "Chirping \(target.pronoun) phone" : "Make \(target.pronoun) phone chirp")
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .font(.nunito(17, .black, relativeTo: .headline))
                .foregroundStyle(Theme.findOnButton)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Theme.findButton, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canPing || pinging)
            .opacity(canPing ? 1 : 0.5)

            Button {
                router.overlay = nil
                router.tab = .talk
            } label: {
                Image(systemName: "mic")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 56, height: 56)
                    .background(Theme.card, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Talk to \(target.name)")
        }
    }
}

/// The design's arrow: `M50 6 L84 74 Q 86 80 80 78 L50 64 L20 78 Q 14 80 16 74 Z`
/// in a 100 x 100 box, rotated about its center by the bearing.
struct FindArrow: Shape {
    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 100
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        var path = Path()
        path.move(to: p(50, 6))
        path.addLine(to: p(84, 74))
        path.addQuadCurve(to: p(80, 78), control: p(86, 80))
        path.addLine(to: p(50, 64))
        path.addLine(to: p(20, 78))
        path.addQuadCurve(to: p(16, 74), control: p(14, 80))
        path.closeSubpath()
        return path
    }
}

/// Plain words for where someone is. Never more than the phone knows.
enum FindWords {
    static func direction(_ bearing: Double) -> String {
        let side = bearing >= 0 ? "right" : "left"
        switch abs(bearing) {
        case ..<10: return "Straight ahead"
        case ..<35: return "Ahead, a little to your \(side)"
        case ..<70: return "Ahead and to your \(side)"
        case ..<110: return "To your \(side)"
        case ..<150: return "Behind you, to your \(side)"
        default: return "Behind you"
        }
    }

    static func spokenDirection(_ bearing: Double) -> String {
        let side = bearing >= 0 ? "right" : "left"
        switch abs(bearing) {
        case ..<10: return "straight ahead"
        case ..<35: return "ahead and a little to the \(side)"
        case ..<70: return "ahead and to the \(side)"
        case ..<110: return "to the \(side)"
        case ..<150: return "behind you and to the \(side)"
        default: return "behind you"
        }
    }

    static func headline(_ f: ChirpCore.Find.Fallback) -> String {
        switch f {
        case .inRange: return "Close by"
        case .throughOthers: return "Further off"
        case .outOfRange: return "Out of range"
        }
    }

    static func line(_ f: ChirpCore.Find.Fallback, name: String) -> String {
        switch f {
        case .inRange: return "Your phone can hear \(name)'s directly"
        case .throughOthers: return "Heard through a friend's phone"
        case .outOfRange(let lastSeen):
            guard let lastSeen else { return "Not heard yet" }
            return "Last heard at \(lastSeen.formatted(date: .omitted, time: .shortened))"
        }
    }

    static func hint(_ f: ChirpCore.Find.Fallback, pronoun: String) -> String {
        switch f {
        case .inRange: return "No arrow on this phone. Make \(pronoun) phone chirp and listen for it."
        case .throughOthers: return "Which way is unknown. Talk or chirp to meet up."
        case .outOfRange: return "We'll keep listening and tell you when \(pronoun) phone is heard."
        }
    }
}

/// Find's demo content, as `Find.dc.html` shows it.
enum FindDemo {
    static let target = (name: Flock.maya.name, palette: Flock.maya.palette, pronoun: "her")
    static let status = "Battery 64% · heard 1 min ago"
    static let state = FindState.pointing(meters: 12, bearing: 18)
}
