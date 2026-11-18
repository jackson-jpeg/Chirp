import SwiftUI
import ChirpCore

@main
struct ChirpApp: App {
    @State private var flock: Flock
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

    init() {
        // Screenshot runs show the design's flock; a real launch has only
        // the flock you started or joined, and the people actually heard.
        let screenshotRun = ProcessInfo.processInfo.arguments.contains("-screen")
        let store: FlockStore? = screenshotRun ? nil : FlockStore()
        let saved = store?.load()
        let flock = screenshotRun ? Flock.demo : Flock.real(flockName: saved?.name)
        let transport = Transport(local: ChirpApp.identity.peerID)
        let audio = AudioSession()
        let captions = LiveCaptions()
        let mesh = Mesh(identity: ChirpApp.identity, flock: flock, transport: transport, flockStore: store)
        _flock = State(initialValue: flock)
        _transport = State(initialValue: transport)
        _audio = State(initialValue: audio)
        _captions = State(initialValue: captions)
        _mesh = State(initialValue: mesh)
        _voice = State(initialValue: Voice(mesh: mesh, audio: audio, captions: captions, flock: flock))
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
                .environment(flock)
                .environment(router)
                .environment(audio)
                .environment(captions)
                .environment(transport)
                .environment(mesh)
                .environment(checkIn)
                .environment(voice)
                .preferredColorScheme(router.forcedScheme)
                .tint(Theme.ink)
                .onOpenURL { url in
                    // An invite link (chirpchirps.com/join or chirpchirps://join).
                    if router.openInvite(url, mesh: mesh, flock: flock) { return }
                    // The Lock Screen card's Talk button (chirpchirps://talk).
                    guard url.scheme == "chirpchirps", url.host() == "talk" else { return }
                    router.overlay = nil
                    router.tab = .talk
                }
                // A link opened from Safari (once universal links are on).
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { _ = router.openInvite(url, mesh: mesh, flock: flock) }
                }
                .task {
                    audio.observeSystem()
                    checkIn.send = { [mesh] lat, lon, accuracy, state in
                        mesh.sendCheckIn(latitude: lat, longitude: lon, accuracy: accuracy, state: state)
                    }
                    checkIn.sendStopped = { [mesh] in mesh.sendCheckInStopped() }
                    // Demo Mode by launch argument (UI tests). People and App Review
                    // come in by Welcome's "Try it with pretend friends".
                    if ProcessInfo.processInfo.arguments.contains("-demo") { router.enterDemo(mesh, flock: flock) }
                    // Sends only while the radio runs.
                    mesh.startHeartbeat()
                }
        }
        // Left the last locked flock (the demo's, say): nobody to share with.
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

    enum OnboardingStep { case welcome, nameFlock, joinFlock, makeBird }

    /// Start or join a flock from Talk's flock menu, once you are onboarded.
    var flockSetup: FlockSetup?
    enum FlockSetup: String, Identifiable { case start, join; var id: String { rawValue } }

    /// You started the flock you are making a bird for (Make your bird says
    /// "Starting" instead of "Joining").
    var startedFlock = false
    /// An invite to another flock while you are in one: asked before switching.
    var pendingInvite: Channel?
    /// An invite link that holds no flock.
    var inviteRefused = false

    /// "Name your flock": a new locked flock with a fresh key, then Make your
    /// bird (or straight back to Talk once onboarded).
    @MainActor
    func startFlock(named raw: String, mesh: Mesh, flock: Flock) {
        let name = FlockInvite.cleanName(raw)
        guard !name.isEmpty else { return }
        startedFlock = true
        use(Channel.newLocked(name: name), mesh: mesh, flock: flock)
    }

    /// A pasted invite or an opened link: join it, or ask first when it
    /// would leave the flock you are in.
    @MainActor
    func join(_ channel: Channel, mesh: Mesh, flock: Flock) {
        if let current = mesh.flockChannel {
            if current.id == channel.id { goToTalk(); return }
            pendingInvite = channel
            return
        }
        startedFlock = false
        use(channel, mesh: mesh, flock: flock)
    }

    /// The answer to "Leave X and join Y?".
    @MainActor
    func confirmPendingInvite(mesh: Mesh, flock: Flock) {
        guard let c = pendingInvite else { return }
        pendingInvite = nil
        startedFlock = false
        use(c, mesh: mesh, flock: flock)
    }

    /// Talk's flock menu: back to Nearby only.
    @MainActor
    func leaveFlock(mesh: Mesh, flock: Flock) {
        mesh.setFlock(nil)
        flock.flockName = ""
    }

    /// Returns true when `url` was an invite link (taken or refused).
    @MainActor
    func openInvite(_ url: URL, mesh: Mesh, flock: Flock) -> Bool {
        guard FlockInvite.isInviteURL(url) else { return false }
        guard !screenshotRun else { return true }
        guard let channel = FlockInvite.parse(url: url) else {
            inviteRefused = true
            return true
        }
        join(channel, mesh: mesh, flock: flock)
        return true
    }

    @MainActor
    private func use(_ channel: Channel, mesh: Mesh, flock: Flock) {
        if mesh.inDemo { leaveDemo(mesh, flock: flock) }
        mesh.setFlock(channel)
        flock.flockName = channel.name
        flockSetup = nil
        if onboarded { goToTalk() } else { onboardingStep = .makeBird }
    }

    private func goToTalk() {
        overlay = nil
        flockSetup = nil
        tab = .talk
    }

    /// Came in by Welcome's "Try it with pretend friends": onboarded for this
    /// launch only (never saved), so leaving the demo goes back to Welcome.
    var demoSkippedOnboarding = false
    /// Your flock's name, put back when the demo ends.
    private var nameBeforeDemo: String?

    init(onboarded: Bool) { self.onboarded = onboarded }

    /// Welcome's demo link: straight onto Talk with a default bird.
    @MainActor
    func enterDemo(_ mesh: Mesh, flock: Flock) {
        if flock.you.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { flock.you.name = "You" }
        mesh.youChanged(flock.you)
        mesh.startDemo()
        nameBeforeDemo = flock.flockName
        flock.flockName = DemoFlock.channel.name
        demoSkippedOnboarding = !onboarded
        overlay = nil
        tab = .talk
        onboarded = true
    }

    /// Talk's demo banner: the pretend friends go, and someone who skipped
    /// Make your bird to get here is back on Welcome.
    @MainActor
    func leaveDemo(_ mesh: Mesh, flock: Flock? = nil) {
        mesh.stopDemo()
        if let flock, let name = nameBeforeDemo { flock.flockName = name }
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
    @Environment(Flock.self) private var flock

    var body: some View {
        @Bindable var router = router
        Group {
            if !router.onboarded {
                switch router.onboardingStep {
                case .welcome: WelcomeView()
                case .nameFlock: NameFlockView { router.onboardingStep = .welcome }
                case .joinFlock: JoinFlockView { router.onboardingStep = .welcome }
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
        .sheet(item: $router.flockSetup) { setup in
            switch setup {
            case .start: NameFlockView { router.flockSetup = nil }
            case .join: JoinFlockView { router.flockSetup = nil }
            }
        }
        .alert("Leave \(flock.displayName) and join \(router.pendingInvite?.name ?? "")?", isPresented: Binding(
            get: { router.pendingInvite != nil }, set: { if !$0 { router.pendingInvite = nil } }
        )) {
            Button("Join") { router.confirmPendingInvite(mesh: mesh, flock: flock) }
            Button("Stay", role: .cancel) {}
        } message: {
            Text("You can be in one flock at a time. To come back, you need an invite again.")
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
