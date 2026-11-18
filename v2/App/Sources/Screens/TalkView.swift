import SwiftUI
import ChirpCore

/// Talk: the birdhouse's line. Built to `v2/design/Talk-Listen` (someone has the
/// line) and `Talk-Hold` (you are talking), plus the quiet line neither file
/// shows. The tab bar under it belongs to MainTabs.
struct TalkView: View {
    @Environment(Birdhouse.self) private var birdhouse
    @Environment(Router.self) private var router
    @Environment(LiveCaptions.self) private var captions
    @Environment(Transport.self) private var transport
    @Environment(Mesh.self) private var mesh
    @Environment(Voice.self) private var voice
    @Environment(Store.self) private var store
    /// The birdhouse size at which the starter last opened Big Birdhouse's card: it
    /// comes back only when the birdhouse grows again.
    @AppStorage("bigBirdhouseCardSeenAt") private var bigBirdhouseCardSeenAt = 0
    @Environment(\.openURL) private var openURL

    @State private var holding = false
    @State private var confirmLeave = false
    @State private var holdStart: Date?
    /// Set when a hold slid away; stays set until the finger lifts.
    @State private var cancelled = false

    private enum Line: Equatable {
        case you
        case listening(Person)
        case quiet
    }

    /// Your microphone is live: the floor is yours, not just your finger down
    /// (a refused hold shows who has the line instead).
    private var talking: Bool { voice.floor.microphoneIsOpen || router.forceTalking }

    private var line: Line {
        if talking { return .you }
        if let t = birdhouse.talker, !t.isYou { return .listening(t) }
        return .quiet
    }

    /// Who sits on the wire: the others, whoever had the line first.
    private var wireBirds: [Person] {
        var list = birdhouse.others
        if let t = birdhouse.talker, let i = list.firstIndex(of: t) {
            list.remove(at: i)
            list.insert(t, at: 0)
        }
        return Array(list.prefix(3))
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    if mesh.inDemo { demoBanner }
                    if !router.screenshotRun || mesh.inDemo { birdhouseAlert }
                    header
                    statusRow
                        .padding(.top, 2)
                        .padding(.horizontal, 20)
                    SceneCard { TalkScene(mode: sceneMode, birds: wireBirds) }
                        .padding(.top, 16)
                        .padding(.horizontal, 16)
                    captionCard
                        .padding(.top, 12)
                        .padding(.horizontal, 16)
                    Spacer(minLength: 28)
                    talkArea
                    Spacer(minLength: 24)
                }
                .frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .foregroundStyle(Theme.ink)
        .sensoryFeedback(.impact(weight: .medium), trigger: holding)
        .animation(.snappy(duration: 0.15), value: talking)
    }

    private var sceneMode: TalkScene.Mode {
        switch line {
        case .you: .holding
        case .listening: .listening
        case .quiet: .quiet
        }
    }

    // MARK: Demo banner

    /// Demo Mode (App Review 2.1(a)): a thin strip over the header, with the
    /// way out. Not in the design files; the copy was approved by Jackson.
    private var demoBanner: some View {
        HStack(spacing: 8) {
            Text("Demo birdhouse. Nothing leaves this phone.")
                .font(.nunito(13, .heavy, relativeTo: .footnote))
                .foregroundStyle(Theme.turnText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Leave demo") { router.leaveDemo(mesh, birdhouse: birdhouse) }
                .font(.nunito(13, .black, relativeTo: .footnote))
                .foregroundStyle(Theme.ink)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .accessibilityIdentifier("talk.leaveDemo")
        }
        .padding(.horizontal, 20)
        .background(Theme.sunGlow)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("talk.demoBanner")
    }

    // MARK: Birdhouse alert

    /// One line under the header, most urgent first: someone asked for help,
    /// a roll call is waiting on you, or a friend just pinged you.
    @ViewBuilder private var birdhouseAlert: some View {
        let me = mesh.dispatch.me
        let board = mesh.rollCalls
        if let first = board.needingHelp(except: me).first {
            alertStrip(text: "\(personName(first)) needs help", action: "See", fill: Theme.dangerSoft,
                       ink: Theme.danger, id: "talk.helpAlert") { router.overlay = .rollCall }
        } else if board.waitingOn(me), let ask = board.ask {
            alertStrip(text: "\(personName(ask.from)) asked: everyone OK?", action: "Answer", fill: Theme.sunGlow,
                       ink: Theme.turnText, id: "talk.rollCallAlert") { router.overlay = .rollCall }
        } else if let ping = mesh.lastPing {
            TimelineView(.periodic(from: .now, by: 5)) { context in
                if context.date.timeIntervalSince(ping.at) < 20 {
                    alertStrip(text: "\(personName(ping.from)) pinged you", action: nil, fill: Theme.signalSoft,
                               ink: Theme.okText, id: "talk.pingAlert") {}
                }
            }
        } else if !mesh.inDemo, BigBirdhouse.showsCard(birds: mesh.birdhouseBirds, startedByMe: mesh.startedBirdhouse,
                                                   unlocked: store.unlocked,
                                                   dismissedAt: bigBirdhouseCardSeenAt == 0 ? nil : bigBirdhouseCardSeenAt) {
            let n = mesh.birdhouseBirds
            alertStrip(text: "\(birdhouse.displayName) has \(n) birds. Big Birdhouse lets it grow.", action: "See",
                       fill: Theme.sunGlow, ink: Theme.turnText, id: "talk.bigBirdhouseCard") {
                bigBirdhouseCardSeenAt = n
                router.bigBirdhouse = .grew(birds: n)
            }
        }
    }

    private func personName(_ peer: PeerID) -> String {
        birdhouse.others.first { $0.peer == peer }?.name ?? mesh.dispatch.roster.person(peer)?.name ?? "Someone"
    }

    private func alertStrip(text: String, action: String?, fill: Color, ink: Color, id: String,
                            perform: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.nunito(14, .black, relativeTo: .subheadline))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let action {
                Button(action, action: perform)
                    .font(.nunito(14, .black, relativeTo: .subheadline))
                    .foregroundStyle(Theme.ink)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 44)
        .background(fill)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            Menu {
                birdhouseMenu
            } label: {
                HStack(spacing: 6) {
                    Text(birdhouse.displayName)
                        .font(.screenTitle)
                        .tracking(-0.3)
                        .multilineTextAlignment(.leading)
                    TalkChevron()
                        .stroke(style: StrokeStyle(lineWidth: 2.8 * 20 / 24, lineCap: .round, lineJoin: .round))
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Theme.ink)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityHint(mesh.birdhouseChannel == nil ? "Start or join a birdhouse" : (mesh.otherBirdhouses.isEmpty ? "Invite friends or leave the birdhouse" : "Invite friends, switch birdhouses or leave"))
            .accessibilityIdentifier("talk.birdhouseMenu")
            .alert("Leave \(birdhouse.displayName)?", isPresented: $confirmLeave) {
                Button("Leave", role: .destructive) { router.leaveBirdhouse(mesh: mesh, birdhouse: birdhouse) }
                Button("Stay", role: .cancel) {}
            } message: {
                Text("To come back, you need an invite again.")
            }

            Spacer(minLength: 12)

            Button {
                router.editingBird = true
            } label: {
                BirdAvatar(palette: birdhouse.you.palette, size: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("You and settings")
        }
        // The files start the header 56 pt from the top of a 390 x 844 phone,
        // whose safe area is 47 pt.
        .padding(.top, 9)
        .padding(.horizontal, 20)
    }

    /// The birdhouse menu under the birdhouse's name: invite by the share sheet
    /// (the link carries the birdhouse's key) and leave; with no birdhouse, start
    /// or join one. Nothing to change while the demo runs.
    @ViewBuilder private var birdhouseMenu: some View {
        if mesh.rollCallChannel != nil {
            Button { router.overlay = .rollCall } label: {
                Label("Roll call: everyone OK?", systemImage: "person.3")
            }
        }
        if mesh.inDemo {
            Text("Pretend birdhouse. Leave the demo to use your own.")
        } else if let channel = mesh.birdhouseChannel, let link = BirdhouseInvite.link(for: channel) {
            // A full free birdhouse you started: Big Birdhouse is offered first. Joiners
            // and owners always share (ChirpCore `BigBirdhouse.invite`).
            if BigBirdhouse.invite(birds: mesh.birdhouseBirds, startedByMe: mesh.startedBirdhouse, unlocked: store.unlocked) == .offerBigBirdhouse {
                Button { router.bigBirdhouse = .invite } label: {
                    Label("Invite friends", systemImage: "person.badge.plus")
                }
            } else {
                ShareLink(item: link,
                          subject: Text("Join \(channel.name) on ChirpChirps"),
                          message: Text("Join my birdhouse on ChirpChirps, so we can talk with no signal. Open this link on your iPhone.")) {
                    Label("Invite friends", systemImage: "person.badge.plus")
                }
            }
            if mesh.startedBirdhouse || store.unlocked {
                Button { router.bigBirdhouse = .menu } label: {
                    Label(store.unlocked ? "Big Birdhouse: yours" : "Big Birdhouse", systemImage: "bird")
                }
            }
            keptBirdhouses
            if mesh.bigBirdhouse {
                // Big Birdhouse keeps this one when you start or join another.
                Button { router.birdhouseSetup = .start } label: { Label("Start another birdhouse", systemImage: "plus") }
                    .accessibilityIdentifier("talk.startAnother")
                Button { router.birdhouseSetup = .join } label: { Label("Join another birdhouse", systemImage: "link") }
            }
            Button(role: .destructive) { confirmLeave = true } label: {
                Label("Leave \(channel.name)", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } else {
            keptBirdhouses
            Button { router.birdhouseSetup = .start } label: { Label("Start a birdhouse", systemImage: "plus") }
            Button { router.birdhouseSetup = .join } label: { Label("Join a birdhouse", systemImage: "link") }
        }
    }

    /// Big Birdhouse keeps the birdhouses you were in: switch back to one
    /// (ChirpCore `SavedBirdhouses`). Nothing shows without it.
    @ViewBuilder private var keptBirdhouses: some View {
        let kept = mesh.otherBirdhouses
        if !kept.isEmpty {
            Section("Your other birdhouses") {
                ForEach(kept, id: \.id) { other in
                    Button {
                        router.switchBirdhouse(to: other.id, mesh: mesh, birdhouse: birdhouse)
                    } label: {
                        Label("Switch to \(other.name)", systemImage: "arrow.left.arrow.right")
                    }
                    .accessibilityIdentifier("talk.switchBirdhouse")
                }
            }
        }
    }

    private var statusRow: some View {
        let n = birdhouse.others.count
        return HStack(spacing: 8) {
            if line == .you {
                TalkDot(fill: Theme.coralHot, ring: Theme.coralSoft)
                Text("You have the line · \(n) hearing you")
                    .foregroundStyle(Theme.danger)
            } else {
                LineBars()
                Text("You + \(n) on the line · all in range")
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .font(.label)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Caption

    @ViewBuilder private var captionCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                switch line {
                case .listening(let talker):
                    captionHeader(dot: TalkDot(fill: Theme.sun, ring: Theme.sunGlow), name: talker.name) {
                        if !router.screenshotRun, let start = voice.floor.speaker?.claimedAt {
                            TimelineView(.periodic(from: start, by: 1)) { tl in
                                Text(TalkDemo.clock(max(0, tl.date.timeIntervalSince(start))))
                            }
                        } else {
                            Text(TalkDemo.listenElapsed)
                        }
                    } meter: {
                        VoiceMeter()
                    }
                    captionLine(listenCaption(talker))
                case .you:
                    captionHeader(dot: TalkDot(fill: Theme.coralHot, ring: Theme.coralSoft), name: "You") {
                        if router.forceTalking || holdStart == nil {
                            Text(TalkDemo.holdElapsed)
                        } else if let start = holdStart {
                            TimelineView(.periodic(from: start, by: 1)) { tl in
                                Text(TalkDemo.clock(tl.date.timeIntervalSince(start)))
                            }
                        }
                    } meter: {
                        VoiceMeter(heights: TalkDemo.holdMeter, played: TalkDemo.holdMeter.count, color: Theme.coralHot)
                    }
                    captionLine(router.screenshotRun || router.forceTalking
                                ? TalkDemo.holdCaption : (voice.myCaption ?? "\u{2026}"))
                case .quiet:
                    HStack(spacing: 8) {
                        TalkDot(fill: Theme.hairline, ring: Theme.quiet)
                        Text("Quiet")
                            .font(.nunito(15, .black, relativeTo: .subheadline))
                    }
                    Text("Hold the button and everyone on the line hears you.")
                        .font(.meta)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .shadow(color: Color.hex(0x14233F, opacity: 0.05), radius: 0, y: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(captionAccessibilityLabel)
        .contextMenu { captionModeMenu }
        .alert("Captions", isPresented: noticeShown) {
            if captions.card == .denied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(captions.notice ?? "")
        }
    }

    /// The card as the design shows it on screenshot runs; otherwise what this
    /// phone allows.
    private var card: CaptionCard { router.screenshotRun ? .captioning : captions.card }

    /// The talker's live caption; the design's words on screenshot runs and
    /// for the demo birdhouse's fixtures, which have no voice.
    private func listenCaption(_ talker: Person) -> String {
        if router.screenshotRun || talker.peer == nil { return TalkDemo.listenCaption }
        return voice.caption(of: talker) ?? "\u{2026}"
    }

    private var noticeShown: Binding<Bool> {
        Binding(get: { captions.notice != nil }, set: { if !$0 { captions.notice = nil } })
    }

    @ViewBuilder private var captionModeMenu: some View {
        Button("Captions on") { captions.send(.chose(.on)) }
        Button("Captions only, no sound") { captions.send(.chose(.only)) }
        Button("Captions off") { captions.send(.chose(.off)) }
    }

    /// The caption under the speaker, or what stands in for it.
    @ViewBuilder private func captionLine(_ text: String) -> some View {
        switch card {
        case .captioning:
            captionText(text)
        case .hidden:
            EmptyView()
        case .offer:
            Button { captions.send(.tappedCaptions) } label: {
                Text("Turn on captions")
                    .font(.nunito(15, .black, relativeTo: .subheadline))
                    .underline()
                    .frame(minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows what people say as text, made on your phone")
        case .denied:
            captionStatus("Captions are off in Settings.")
        case .unavailable:
            captionStatus("Captions are not available for your language yet.")
        }
    }

    private func captionStatus(_ s: String) -> some View {
        Text(s)
            .font(.meta)
            .foregroundStyle(Theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var captionAccessibilityLabel: String {
        let who: String
        let said: String
        switch line {
        case .listening(let t): who = t.name; said = listenCaption(t)
        case .you: who = "You"; said = TalkDemo.holdCaption
        case .quiet: return "The line is quiet."
        }
        switch card {
        case .captioning: return "Live caption. \(who): \(said)"
        case .hidden: return "\(who) is talking."
        case .offer: return "\(who) is talking. Captions are not on yet."
        case .denied: return "\(who) is talking. Captions are off in Settings."
        case .unavailable: return "\(who) is talking. Captions are not available for your language yet."
        }
    }

    private func captionHeader<Time: View, Meter: View>(dot: TalkDot, name: String,
                                                        @ViewBuilder time: () -> Time,
                                                        @ViewBuilder meter: () -> Meter) -> some View {
        HStack(spacing: 8) {
            dot
            Text(name)
                .font(.nunito(15, .black, relativeTo: .subheadline))
            time()
                .font(.meta)
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
            Spacer(minLength: 8)
            meter()
                .frame(width: 74)
        }
    }

    private func captionText(_ s: String) -> some View {
        Text("\u{201C}\(s)\u{201D}")
            .font(.bodyHeavy)
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Talk button

    private var talkArea: some View {
        VStack(spacing: 8) {
            TalkButtonFace(talking: talking, palette: birdhouse.you.palette)
                .contentShape(Circle())
                .gesture(holdGesture)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(talking ? "Talking, let go to send" : "Hold to talk")
                .accessibilityHint(talking
                    ? "Double tap to send. Or use the Cancel action."
                    : "Touch and hold to talk to everyone on the line. With VoiceOver, double tap to start and double tap again to send.")
                .accessibilityAddTraits(talking ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction {
                    if holding { send() } else if !router.forceTalking { start() }
                }
                .accessibilityActions {
                    if holding {
                        Button("Cancel") { cancel() }
                    }
                }

            Text(talking ? "Talking\u{2026} let go to send" : "Hold to talk")
                .font(.nunito(21, .black, relativeTo: .title3))
                .padding(.top, talking ? 6 : 0)
                .accessibilityHidden(true)
            Text(subtitle)
                .font(.meta)
                .foregroundStyle(Theme.inkSecondary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }

    private var subtitle: String {
        switch line {
        case .you: "Slide away to cancel"
        case .listening(let t): "\(t.name) has the line. You're up next."
        case .quiet: "The line is quiet."
        }
    }

    /// Press and hold to talk; let go to send; slide 120 pt away to cancel.
    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !cancelled, !router.forceTalking else { return }
                if !holding { start() }
                let t = value.translation
                if (t.width * t.width + t.height * t.height).squareRoot() > 120 { cancel() }
            }
            .onEnded { _ in
                if holding { send() }
                cancelled = false
            }
    }

    private func start() {
        holding = true
        holdStart = .now
        // The first hold is the tap that needs other phones: Local Network asks now.
        transport.start()
        // Asks for the line; the microphone opens only if it is free.
        voice.press()
    }

    private func send() {
        holding = false
        holdStart = nil
        voice.release()
    }

    private func cancel() {
        holding = false
        holdStart = nil
        cancelled = true
        // Live voice is already out, so a slide-away ends the turn like a
        // release; what matters is that the microphone closes now.
        voice.release()
    }
}

/// A 10 pt dot with a 3 pt soft ring (`box-shadow: 0 0 0 3px`).
struct TalkDot: View {
    var fill: Color
    var ring: Color
    var body: some View {
        ZStack {
            Circle().fill(ring).frame(width: 16, height: 16)
            Circle().fill(fill).frame(width: 10, height: 10)
        }
        .frame(width: 10, height: 10)
        .accessibilityHidden(true)
    }
}

/// The header's `M6 9l6 6 6-6` chevron in a 24 box, drawn at 20 pt.
struct TalkChevron: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 24
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + 6 * k, y: rect.minY + 9 * k))
        p.addLine(to: CGPoint(x: rect.minX + 12 * k, y: rect.minY + 15 * k))
        p.addLine(to: CGPoint(x: rect.minX + 18 * k, y: rect.minY + 9 * k))
        return p
    }
}

/// Demo Mode content for Talk, the same words the design files show.
enum TalkDemo {
    static let listenCaption = "We got a table by the fire. Lodge, second floor, come up when you're done."
    static let listenElapsed = "0:06"
    static let holdCaption = "Be there in five. Save me a seat by the fire."
    static let holdElapsed = "0:03"
    static let holdMeter: [CGFloat] = [8, 16, 20, 12, 18, 10, 14, 8, 16, 10, 6]

    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return "\(s / 60):" + (s % 60 < 10 ? "0" : "") + "\(s % 60)"
    }
}
