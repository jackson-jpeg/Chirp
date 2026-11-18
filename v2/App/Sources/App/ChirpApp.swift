import SwiftUI
import ChirpCore

@main
struct ChirpApp: App {
    @State private var birdhouse: Birdhouse
    @State private var router = Router.fromLaunchArguments()
    /// Opens nothing until someone talks; closes on background (2.5.4).
    @State private var audio: AudioSession
    /// Reads the speech status only; asks on the first tap of captions.
    @State private var captions: LiveCaptions
    /// The radio. Starts on the first hold to talk, not at launch (5.1.1(iv)).
    @State private var transport: Transport
    /// Every packet in and out goes through ChirpCore's `Dispatch` here.
    /// Making it starts nothing: the radio still waits for the first hold.
    @State private var mesh: Mesh
    /// Check-in: off at every launch, asked every time (5.1.2(i)).
    @State private var checkIn = CheckInLocation()
    /// Talk's floor and live voice, between the mesh and the audio session.
    @State private var voice: Voice
    /// Big Birdhouse, the one purchase. Reads what is owned; asks nothing.
    @State private var store = Store()

    init() {
        // Screenshot runs show the design's birdhouse; a real launch has only
        // the birdhouse you started or joined, and the people actually heard.
        let screenshotRun = ProcessInfo.processInfo.arguments.contains("-screen")
        let store: BirdhouseStore? = screenshotRun ? nil : BirdhouseStore()
        let saved = store?.load()
        let birdhouse = screenshotRun ? Birdhouse.demo : Birdhouse.real(birdhouseName: saved?.name)
        let transport = Transport(local: ChirpApp.identity.peerID)
        let audio = AudioSession()
        let captions = LiveCaptions()
        let mesh = Mesh(identity: ChirpApp.identity, birdhouse: birdhouse, transport: transport, birdhouseStore: store)
        _birdhouse = State(initialValue: birdhouse)
        _transport = State(initialValue: transport)
        _audio = State(initialValue: audio)
        _captions = State(initialValue: captions)
        _mesh = State(initialValue: mesh)
        _voice = State(initialValue: Voice(mesh: mesh, audio: audio, captions: captions, birdhouse: birdhouse))
    }
    /// Created on first launch and kept in the Keychain.
    static let identity: LocalIdentity = {
        do { return try LocalIdentity.loadOrCreate(from: KeychainStore()) } catch {
            // The Keychain refused: run with a key for this launch only.
            return LocalIdentity(signingKey: .init(), agreementKey: .init())
        }
    }()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(birdhouse)
                .environment(router)
                .environment(audio)
                .environment(captions)
                .environment(transport)
                .environment(mesh)
                .environment(checkIn)
                .environment(voice)
                .environment(store)
                .preferredColorScheme(router.forcedScheme)
                .tint(Theme.ink)
                .onOpenURL { url in
                    // An invite link (chirpchirps.com/join or chirpchirps://join).
                    if router.openInvite(url, mesh: mesh, birdhouse: birdhouse) { return }
                    // The Lock Screen card's Talk button (chirpchirps://talk).
                    guard url.scheme == "chirpchirps", url.host() == "talk" else { return }
                    router.overlay = nil
                    router.tab = .talk
                }
                // A link opened from Safari (once universal links are on).
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { _ = router.openInvite(url, mesh: mesh, birdhouse: birdhouse) }
                }
                .task {
                    audio.observeSystem()
                    store.start()
                    checkIn.send = { [mesh] lat, lon, accuracy, state in
                        mesh.sendCheckIn(latitude: lat, longitude: lon, accuracy: accuracy, state: state)
                    }
                    checkIn.sendStopped = { [mesh] in mesh.sendCheckInStopped() }
                    // Demo Mode by launch argument (UI tests). People and App Review
                    // come in by Welcome's "Try it with pretend friends".
                    if ProcessInfo.processInfo.arguments.contains("-demo") { router.enterDemo(mesh, birdhouse: birdhouse) }
                    // Sends only while the radio runs.
                    mesh.startHeartbeat()
                }
        }
        // Left the last locked birdhouse (the demo's, say): nobody to share with.
        .onChange(of: "\(birdhouse.you.name)|\(birdhouse.you.palette.index)|\(birdhouse.you.chirp)") { _, _ in
            mesh.youChanged(birdhouse.you)
        }
        // A refund (or another Apple Account) takes Big Birdhouse away: a bird
        // never keeps a color or chirp it no longer owns. Only once the App
        // Store has answered, so a launch never resets a paid choice.
        .onChange(of: store.checked && !store.unlocked) { _, lost in
            guard lost else { return }
            let p = BigBirdhouse.allowedPalette(birdhouse.you.palette.index, unlocked: false)
            if p != birdhouse.you.palette.index { birdhouse.you.palette = BirdPalette.all[p] }
            birdhouse.you.chirp = BigBirdhouse.allowedChirp(birdhouse.you.chirp, unlocked: false)
        }
        // Kept birdhouses are offered only while Big Birdhouse is owned.
        .onChange(of: store.unlocked, initial: true) { _, owned in
            mesh.bigBirdhouse = owned
        }
        .onChange(of: mesh.canCheckIn) { _, can in
            if !can { checkIn.stop() }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // Off the screen, the turn ends (the session closes with it).
            if phase != .active { voice.release() }
            audio.follow(phase)
            transport.follow(phase)
            mesh.inBackground = phase == .background
            checkIn.follow(phase)
            if phase == .active { captions.refresh() }
        }
    }
}

/// Every screen in the approved design, by the name of its file in
/// `v2/design/`. Launch with `-screen <name>` (and `-dark` for the dark
/// version) to open straight onto one, which is how the build-vs-design
/// screenshots are taken.
enum Screen: String, CaseIterable, Identifiable {
    case welcome = "Welcome"
    case makeBird = "MakeBird"
    case talkListen = "Talk-Listen"
    case talkHold = "Talk-Hold"
    case chat = "Chat"
    case nearby = "Nearby"
    case find = "Find"
    case meetup = "Meetup"
    case rollCall = "RollCall"
    case catchUp = "CatchUp"
    var id: String { rawValue }
}

enum Tab: Hashable { case talk, chat, nearby }

@Observable
final class Router {
    var onboarded: Bool
    var onboardingStep: OnboardingStep = .welcome
    var tab: Tab = .talk
    /// A sheet or pushed screen over the tabs (Find, Meet-up, Roll call, Catch up).
    var overlay: Screen?
    /// Who Find is finding (a `Person.id`); nil shows the design's friend.
    var findTarget: String?

    func find(_ person: Person) {
        findTarget = person.id
        overlay = .find
    }
    /// Only for the screenshot runs: the Talk screen's "you are talking" state.
    var forceTalking = false
    var forcedScheme: ColorScheme?
    /// Launched with `-screen`: show the design's content (captions included)
    /// whatever this simulator has been allowed.
    var screenshotRun = false

    enum OnboardingStep { case welcome, nameBirdhouse, joinBirdhouse, makeBird }

    /// Start or join a birdhouse from Talk's birdhouse menu, once you are onboarded.
    var birdhouseSetup: BirdhouseSetup?
    /// Big Birdhouse's sheet (the one purchase), and why it opened.
    var bigBirdhouse: BigBirdhouseReason?
    /// Make your bird again, from Talk's "You and settings".
    var editingBird = false
    enum BirdhouseSetup: String, Identifiable { case start, join; var id: String { rawValue } }

    /// You started the birdhouse you are making a bird for (Make your bird says
    /// "Starting" instead of "Joining").
    var startedBirdhouse = false
    /// An invite to another birdhouse while you are in one: asked before switching.
    var pendingInvite: Channel?
    /// An invite link that holds no birdhouse.
    var inviteRefused = false

    /// "Name your birdhouse": a new locked birdhouse with a fresh key, then Make your
    /// bird (or straight back to Talk once onboarded).
    @MainActor
    func startBirdhouse(named raw: String, mesh: Mesh, birdhouse: Birdhouse) {
        let name = BirdhouseInvite.cleanName(raw)
        guard !name.isEmpty else { return }
        startedBirdhouse = true
        use(Channel.newLocked(name: name), mesh: mesh, birdhouse: birdhouse, started: true)
    }

    /// A pasted invite or an opened link: join it, or ask first when it
    /// would leave the birdhouse you are in.
    @MainActor
    func join(_ channel: Channel, mesh: Mesh, birdhouse: Birdhouse) {
        switch mesh.joining(channel) {
        case .alreadyIn: goToTalk()
        case .askToLeave: pendingInvite = channel
        case .use:
            startedBirdhouse = false
            use(channel, mesh: mesh, birdhouse: birdhouse)
        }
    }

    /// Talk's birdhouse menu, with Big Birdhouse: back onto a kept birdhouse.
    @MainActor
    func switchBirdhouse(to id: ChannelID, mesh: Mesh, birdhouse: Birdhouse) {
        mesh.switchBirdhouse(to: id)
        if let now = mesh.birdhouseChannel, now.id == id { birdhouse.birdhouseName = now.name }
        goToTalk()
    }

    /// The answer to "Leave X and join Y?".
    @MainActor
    func confirmPendingInvite(mesh: Mesh, birdhouse: Birdhouse) {
        guard let c = pendingInvite else { return }
        pendingInvite = nil
        startedBirdhouse = false
        use(c, mesh: mesh, birdhouse: birdhouse)
    }

    /// Talk's birdhouse menu: back to Nearby only.
    @MainActor
    func leaveBirdhouse(mesh: Mesh, birdhouse: Birdhouse) {
        mesh.setBirdhouse(nil)
        birdhouse.birdhouseName = ""
    }

    /// Returns true when `url` was an invite link (taken or refused).
    @MainActor
    func openInvite(_ url: URL, mesh: Mesh, birdhouse: Birdhouse) -> Bool {
        guard BirdhouseInvite.isInviteURL(url) else { return false }
        guard !screenshotRun else { return true }
        guard let channel = BirdhouseInvite.parse(url: url) else {
            inviteRefused = true
            return true
        }
        join(channel, mesh: mesh, birdhouse: birdhouse)
        return true
    }

    @MainActor
    private func use(_ channel: Channel, mesh: Mesh, birdhouse: Birdhouse, started: Bool = false) {
        if mesh.inDemo { leaveDemo(mesh, birdhouse: birdhouse) }
        mesh.setBirdhouse(channel, started: started)
        birdhouse.birdhouseName = channel.name
        birdhouseSetup = nil
        if onboarded { goToTalk() } else { onboardingStep = .makeBird }
    }

    private func goToTalk() {
        overlay = nil
        birdhouseSetup = nil
        tab = .talk
    }

    /// Came in by Welcome's "Try it with pretend friends": onboarded for this
    /// launch only (never saved), so leaving the demo goes back to Welcome.
    var demoSkippedOnboarding = false
    /// Your birdhouse's name, put back when the demo ends.
    private var nameBeforeDemo: String?

    init(onboarded: Bool) { self.onboarded = onboarded }

    /// Welcome's demo link: straight onto Talk with a default bird.
    @MainActor
    func enterDemo(_ mesh: Mesh, birdhouse: Birdhouse) {
        if birdhouse.you.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { birdhouse.you.name = "You" }
        mesh.youChanged(birdhouse.you)
        mesh.startDemo()
        nameBeforeDemo = birdhouse.birdhouseName
        birdhouse.birdhouseName = DemoBirdhouse.channel.name
        demoSkippedOnboarding = !onboarded
        overlay = nil
        tab = .talk
        onboarded = true
    }

    /// Talk's demo banner: the pretend friends go, and someone who skipped
    /// Make your bird to get here is back on Welcome.
    @MainActor
    func leaveDemo(_ mesh: Mesh, birdhouse: Birdhouse? = nil) {
        mesh.stopDemo()
        if let birdhouse, let name = nameBeforeDemo { birdhouse.birdhouseName = name }
        nameBeforeDemo = nil
        overlay = nil
        if demoSkippedOnboarding {
            demoSkippedOnboarding = false
            onboardingStep = .welcome
            onboarded = false
        }
    }

    static func fromLaunchArguments(_ args: [String] = ProcessInfo.processInfo.arguments) -> Router {
        let r = Router(onboarded: true)
        if args.contains("-dark") { r.forcedScheme = .dark }
        if args.contains("-light") { r.forcedScheme = .light }
        guard let i = args.firstIndex(of: "-screen"), i + 1 < args.count, let s = Screen(rawValue: args[i + 1]) else {
            r.onboarded = UserDefaults.standard.bool(forKey: "onboarded")
            return r
        }
        r.show(s)
        r.screenshotRun = true
        return r
    }

    func show(_ s: Screen) {
        overlay = nil
        forceTalking = false
        switch s {
        case .welcome: onboarded = false; onboardingStep = .welcome
        case .makeBird: onboarded = false; onboardingStep = .makeBird
        case .talkListen: onboarded = true; tab = .talk
        case .talkHold: onboarded = true; tab = .talk; forceTalking = true
        case .chat: onboarded = true; tab = .chat
        case .nearby: onboarded = true; tab = .nearby
        case .find, .meetup, .rollCall, .catchUp: onboarded = true; tab = .talk; overlay = s
        }
    }
}

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(Mesh.self) private var mesh
    @Environment(Birdhouse.self) private var birdhouse

    var body: some View {
        @Bindable var router = router
        Group {
            if !router.onboarded {
                switch router.onboardingStep {
                case .welcome: WelcomeView()
                case .nameBirdhouse: NameBirdhouseView { router.onboardingStep = .welcome }
                case .joinBirdhouse: JoinBirdhouseView { router.onboardingStep = .welcome }
                case .makeBird: MakeBirdView()
                }
            } else {
                MainTabs()
            }
        }
        .fullScreenCover(item: $router.overlay) { screen in
            switch screen {
            case .find: FindView()
            case .meetup: MeetupView()
            case .rollCall: RollCallView()
            case .catchUp: CatchUpView()
            default: EmptyView()
            }
        }
        .sheet(item: $router.bigBirdhouse) { reason in
            BigBirdhouseView(reason: reason)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $router.editingBird) {
            MakeBirdView(editing: true)
        }
        .sheet(item: $router.birdhouseSetup) { setup in
            switch setup {
            case .start: NameBirdhouseView { router.birdhouseSetup = nil }
            case .join: JoinBirdhouseView { router.birdhouseSetup = nil }
            }
        }
        .alert("Leave \(birdhouse.displayName) and join \(router.pendingInvite?.name ?? "")?", isPresented: Binding(
            get: { router.pendingInvite != nil }, set: { if !$0 { router.pendingInvite = nil } }
        )) {
            Button("Join") { router.confirmPendingInvite(mesh: mesh, birdhouse: birdhouse) }
            Button("Stay", role: .cancel) {}
        } message: {
            Text("You can be in one birdhouse at a time. To come back, you need an invite again.")
        }
        .alert("This invite link is not complete", isPresented: $router.inviteRefused) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Ask your friend to send the link again.")
        }
    }
}

/// Talk, Chat, Nearby with the design's own bar: white, a hairline on top, the
/// selected tab in a sun pill.
struct MainTabs: View {
    @Environment(Router.self) private var router

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch router.tab {
                case .talk: TalkView()
                case .chat: ChatView()
                case .nearby: NearbyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            TabBar()
        }
        .screenBackground()
    }
}

struct TabBar: View {
    @Environment(Router.self) private var router

    var body: some View {
        HStack {
            item(.talk, "Talk", "mic")
            item(.chat, "Chat", "bubble.left")
            item(.nearby, "Nearby", "safari")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Theme.card.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func item(_ tab: Tab, _ title: String, _ symbol: String) -> some View {
        let selected = router.tab == tab
        return Button { router.tab = tab } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: selected ? .bold : .semibold))
                    .frame(width: 24, height: 24)
                    .padding(.horizontal, 18).padding(.vertical, 4)
                    .background(selected ? Theme.sunSoft : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(title).font(.tab.weight(selected ? .black : .heavy))
            }
            .foregroundStyle(selected ? Theme.ink : Theme.inkSecondary)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
