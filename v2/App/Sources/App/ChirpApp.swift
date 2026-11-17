import SwiftUI
import ChirpCore

@main
struct ChirpApp: App {
    @State private var flock: Flock
    @State private var router = Router.fromLaunchArguments()
    /// Opens nothing until someone talks; closes on background (2.5.4).
    @State private var audio = AudioSession()
    /// Reads the speech status only; asks on the first tap of captions.
    @State private var captions = LiveCaptions()
    /// The radio. Starts on the first hold to talk, not at launch (5.1.1(iv)).
    @State private var transport: Transport
    /// Every packet in and out goes through ChirpCore's `Dispatch` here.
    /// Making it starts nothing: the radio still waits for the first hold.
    @State private var mesh: Mesh

    init() {
        let flock = Flock.demo
        let transport = Transport(local: ChirpApp.identity.peerID)
        _flock = State(initialValue: flock)
        _transport = State(initialValue: transport)
        _mesh = State(initialValue: Mesh(identity: ChirpApp.identity, flock: flock, transport: transport))
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
                .preferredColorScheme(router.forcedScheme)
                .tint(Theme.ink)
                // The Lock Screen card's Talk button (chirpchirps://talk).
                .onOpenURL { url in
                    guard url.scheme == "chirpchirps", url.host() == "talk" else { return }
                    router.overlay = nil
                    router.tab = .talk
                }
                .task {
                    audio.observeSystem()
                    // Demo Mode for App Review; the visible way in is still to come (docs/NEXT.md).
                    if ProcessInfo.processInfo.arguments.contains("-demo") { mesh.startDemo() }
                    // Sends only while the radio runs.
                    mesh.startHeartbeat()
                }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            audio.follow(phase)
            transport.follow(phase)
            mesh.inBackground = phase == .background
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

    enum OnboardingStep { case welcome, makeBird }

    init(onboarded: Bool) { self.onboarded = onboarded }

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

    var body: some View {
        @Bindable var router = router
        Group {
            if !router.onboarded {
                switch router.onboardingStep {
                case .welcome: WelcomeView()
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
