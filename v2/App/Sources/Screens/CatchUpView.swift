import SwiftUI

/// Catch up: the chirps you missed while out of range, played in order. Built
/// to `v2/design/CatchUp.dc.html`. Playing only changes state for now.
struct CatchUpView: View {
    @Environment(Router.self) private var router
    @State private var playing = false
    @State private var speed: CatchUpSpeed = .oneAndHalf
    /// Which chirp is playing (the first, until audio is wired in).
    @State private var current = 0

    private let items = CatchUpDemo.items

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 9)
                player
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                list
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .foregroundStyle(Theme.ink)
        .screenBackground()
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            CoverBackButton(title: "Talk") {
                router.overlay = nil
                router.tab = .talk
            }
            Text("You missed \(items.count) chirps")
                .font(.nunito(32, .black, relativeTo: .largeTitle))
                .tracking(-0.32)
                .accessibilityAddTraits(.isHeader)
            Text(CatchUpDemo.summary)
                .font(.nunito(15, .bold, relativeTo: .subheadline))
                .foregroundStyle(Theme.inkSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Player

    private var player: some View {
        HStack(spacing: 12) {
            Button {
                playing.toggle()
                if playing { current = 0 }
                // TODO: play the held chirps in order at `speed.rate`, skipping
                // silence (ChirpCore CatchUp), advancing `current` as each ends.
            } label: {
                ZStack {
                    Circle().fill(Theme.sun)
                    if playing {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 1.5).frame(width: 5, height: 16)
                            RoundedRectangle(cornerRadius: 1.5).frame(width: 5, height: 16)
                        }
                        .foregroundStyle(BirdRenderer.ink)
                    } else {
                        CatchUpPlayTriangle()
                            .fill(BirdRenderer.ink)
                            .frame(width: 18, height: 18)
                    }
                }
                .frame(width: 52, height: 52)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playing ? "Pause" : "Play all")

            VStack(alignment: .leading, spacing: 0) {
                Text(playing ? "Playing \(current + 1) of \(items.count)" : "Play all in order")
                    .font(.nunito(17, .black, relativeTo: .headline))
                    .foregroundStyle(.white)
                Text("\(speed.duration(of: CatchUpDemo.totalSeconds)) at \(speed.label) · skips silence")
                    .font(.nunito(14, .bold, relativeTo: .subheadline))
                    .foregroundStyle(Theme.playerSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)

            Button {
                speed = speed.next
            } label: {
                Text(speed.label)
                    .font(.nunito(14, .black, relativeTo: .subheadline))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(minWidth: 52, minHeight: 36)
                    .overlay(Capsule().strokeBorder(Theme.playerRim, lineWidth: 2))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Speed \(speed.label)")
            .accessibilityHint("Changes how fast the chirps play")
        }
        .padding(12)
        .background(Theme.player, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: Missed chirps

    private var list: some View {
        VStack(spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item, isCurrent: playing && index == current)
            }
        }
    }

    private func row(_ item: CatchUpDemo.Item, isCurrent: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CoverBirdDisc(palette: item.palette, diameter: 40, center: CGPoint(x: 17, y: 25), scale: 0.12)
            VStack(alignment: .leading, spacing: item.meetup == nil ? 2 : 8) {
                Text("\(Text(item.name).font(.nunito(14, .black, relativeTo: .subheadline)))\(Text(" · \(item.meta)").foregroundStyle(Theme.inkSecondary))")
                    .font(.nunito(14, .bold, relativeTo: .subheadline))
                if let quote = item.quote {
                    Text("“\(quote)”")
                        .font(.nunito(16, .bold, relativeTo: .body))
                }
                if let meetup = item.meetup {
                    Button {
                        router.overlay = .meetup
                    } label: {
                        HStack(spacing: 10) {
                            CatchUpFlagIcon()
                                .stroke(Theme.purple, style: .init(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                                .frame(width: 22, height: 22)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(meetup.title)
                                    .font(.nunito(15, .black, relativeTo: .subheadline))
                                    .foregroundStyle(Theme.ink)
                                Text(meetup.detail)
                                    .font(.nunito(13, .bold, relativeTo: .footnote))
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                            .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.purpleSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the meet-up")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.sun, lineWidth: 3)
            }
        }
        .accessibilityElement(children: item.meetup == nil ? .combine : .contain)
    }
}

/// Playback speeds; the speed chip cycles through them.
enum CatchUpSpeed: CaseIterable {
    case one, oneAndHalf, two

    var rate: Double {
        switch self {
        case .one: return 1
        case .oneAndHalf: return 1.5
        case .two: return 2
        }
    }

    var label: String {
        switch self {
        case .one: return "1x"
        case .oneAndHalf: return "1.5x"
        case .two: return "2x"
        }
    }

    var next: CatchUpSpeed {
        switch self {
        case .one: return .oneAndHalf
        case .oneAndHalf: return .two
        case .two: return .one
        }
    }

    /// "0:41" for the whole catch-up at this speed.
    func duration(of seconds: Double) -> String {
        let s = Int((seconds / rate).rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// The play triangle: `M3 1.5 L12 7 L3 12.5 Z` in a 14 box.
struct CatchUpPlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 14
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + 3 * k, y: rect.minY + 1.5 * k))
        p.addLine(to: CGPoint(x: rect.minX + 12 * k, y: rect.minY + 7 * k))
        p.addLine(to: CGPoint(x: rect.minX + 3 * k, y: rect.minY + 12.5 * k))
        p.closeSubpath()
        return p
    }
}

/// The meet-up flag: `M5 21V4 M5 4h12l-3 4 3 4H5` in a 24 box.
struct CatchUpFlagIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 24
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        var p = Path()
        p.move(to: pt(5, 21)); p.addLine(to: pt(5, 4))
        p.move(to: pt(5, 4))
        p.addLine(to: pt(17, 4))
        p.addLine(to: pt(14, 8))
        p.addLine(to: pt(17, 12))
        p.addLine(to: pt(5, 12))
        return p
    }
}

/// Catch up's demo content, as `CatchUp.dc.html` shows it.
enum CatchUpDemo {
    struct Meetup { var title: String; var detail: String }

    struct Item: Identifiable {
        var id: Int
        var name: String
        var palette: BirdPalette
        var meta: String
        var quote: String?
        var meetup: Meetup?
    }

    static let summary = "Out of range from 9:52 to 10:07. Friends' phones held them for you."
    /// The whole catch-up at 1x, silences skipped: 0:41 at 1.5x as designed.
    static let totalSeconds: Double = 61.5

    static let items: [Item] = [
        Item(id: 0, name: Flock.jon.name, palette: Flock.jon.palette, meta: "9:55 · 0:08",
             quote: "Lift 4 is closed, wind. Going to the blue gondola instead."),
        Item(id: 1, name: Flock.maya.name, palette: Flock.maya.palette, meta: "9:58 · 0:05",
             quote: "Same. Grabbing coffee at the bottom."),
        Item(id: 2, name: Flock.jon.name, palette: Flock.jon.palette, meta: "10:01",
             meetup: Meetup(title: "Meet-up: blue gondola", detail: "3:30 PM · 420 m from you")),
        Item(id: 3, name: Flock.priya.name, palette: Flock.priya.palette, meta: "10:04 · 0:03",
             quote: "See you there!"),
    ]
}
