import SwiftUI

/// Talk: the flock's line. Built to `v2/design/Talk-Listen` (someone has the
/// line) and `Talk-Hold` (you are talking), plus the quiet line neither file
/// shows. The tab bar under it belongs to MainTabs.
struct TalkView: View {
    @Environment(Flock.self) private var flock
    @Environment(Router.self) private var router

    @State private var holding = false
    @State private var holdStart: Date?
    /// Set when a hold slid away; stays set until the finger lifts.
    @State private var cancelled = false

    private enum Line: Equatable {
        case you
        case listening(Person)
        case quiet
    }

    private var talking: Bool { holding || router.forceTalking }

    private var line: Line {
        if talking { return .you }
        if let t = flock.talker, !t.isYou { return .listening(t) }
        return .quiet
    }

    /// Who sits on the wire: the others, whoever had the line first.
    private var wireBirds: [Person] {
        var list = flock.others
        if let t = flock.talker, let i = list.firstIndex(of: t) {
            list.remove(at: i)
            list.insert(t, at: 0)
        }
        return Array(list.prefix(3))
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
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

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            Button {
                // TODO: open the flock switcher.
            } label: {
                HStack(spacing: 6) {
                    Text(flock.flockName)
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
            .accessibilityHint("Shows your flocks")

            Spacer(minLength: 12)

            Button {
                // TODO: open You and settings.
            } label: {
                BirdAvatar(palette: flock.you.palette, size: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("You and settings")
        }
        // The files start the header 56 pt from the top of a 390 x 844 phone,
        // whose safe area is 47 pt.
        .padding(.top, 9)
        .padding(.horizontal, 20)
    }

    private var statusRow: some View {
        let n = flock.others.count
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
                        // TODO: the talker's live elapsed time from the floor.
                        Text(TalkDemo.listenElapsed)
                    } meter: {
                        VoiceMeter()
                    }
                    captionText(TalkDemo.listenCaption)
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
                    // TODO: your live caption from speech recognition.
                    captionText(TalkDemo.holdCaption)
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
    }

    private var captionAccessibilityLabel: String {
        switch line {
        case .listening(let t): "Live caption. \(t.name): \(TalkDemo.listenCaption)"
        case .you: "Live caption. You: \(TalkDemo.holdCaption)"
        case .quiet: "The line is quiet."
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
            TalkButtonFace(talking: talking, palette: flock.you.palette)
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
        // TODO: open the floor: ask for the line and start the microphone.
    }

    private func send() {
        holding = false
        holdStart = nil
        // TODO: close the floor: stop the microphone and send what was said.
    }

    private func cancel() {
        holding = false
        holdStart = nil
        cancelled = true
        // TODO: drop the recording and give the line back without sending.
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
