import SwiftUI

/// Your answer to a meet-up.
enum MeetupRSVP: String, CaseIterable, Identifiable {
    case onMyWay = "On my way"
    case runningLate = "Running late"
    case cantMakeIt = "Can't make it"
    var id: String { rawValue }
}

/// Meet-up spot: where, when, how far, and who's coming. Built to
/// `v2/design/Meetup.dc.html`.
struct MeetupView: View {
    @Environment(Router.self) private var router
    @Environment(Flock.self) private var flock
    @State private var rsvp: MeetupRSVP = .onMyWay

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 9)
                spotCard
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                comingCard
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                rsvpRow
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .foregroundStyle(Theme.ink)
        .screenBackground()
    }

    // MARK: Header

    private var header: some View {
        HStack {
            CoverBackButton(title: "Chat") {
                router.overlay = nil
                router.tab = .chat
            }
            Spacer()
            Button {
                // TODO: edit the meet-up (place and time); only its setter or
                // anyone? Decide with the Chat meet-up composer.
            } label: {
                Text("Edit")
                    .font(.nunito(16, .heavy, relativeTo: .body))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 4)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit meet-up")
        }
    }

    // MARK: The spot

    private var spotCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            MeetupHillScene()
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Meet-up · set by \(MeetupDemo.setBy.name)".uppercased())
                    .font(.nunito(13, .black, relativeTo: .caption))
                    .tracking(1.04)
                    .foregroundStyle(Theme.purple)
                Text(MeetupDemo.place)
                    .font(.nunito(26, .black, relativeTo: .title))
                    .accessibilityAddTraits(.isHeader)
                Text(MeetupDemo.when)
                    .font(.nunito(16, .heavy, relativeTo: .body))
                    .foregroundStyle(Theme.inkBody)
                directions
                    .padding(.top, 10)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 16)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Theme.shadow, radius: 15, y: 10)
    }

    private var directions: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.solid)
                MeetupPointer()
                    .fill(Theme.onSolid)
                    .rotationEffect(.degrees(-30))
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(MeetupDemo.distance)
                    .font(.nunito(17, .black, relativeTo: .headline))
                Text(MeetupDemo.travel)
                    .font(.nunito(14, .bold, relativeTo: .subheadline))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Button {
                // TODO: guide to the spot. NearbyInteraction cannot point to a
                // place, so this needs a compass bearing from the setter's shared
                // location (LocationConsent) once location sharing is wired in.
            } label: {
                Text("Guide me")
                    .font(.nunito(15, .black, relativeTo: .subheadline))
                    .foregroundStyle(Theme.onSolid)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Theme.solid, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.morning, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Who's coming

    private var comingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Who's coming")
                .font(.nunito(15, .black, relativeTo: .subheadline))
                .foregroundStyle(Theme.inkSecondary)
                .padding(.top, 10)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            let rows = MeetupDemo.rows(you: flock.you, yourAnswer: rsvp)
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                comingRow(row)
                    .overlay(alignment: .bottom) {
                        if index < rows.count - 1 {
                            Rectangle().fill(Theme.quiet).frame(height: 1)
                        }
                    }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func comingRow(_ row: MeetupDemo.Row) -> some View {
        HStack(spacing: 12) {
            CoverBirdDisc(palette: row.palette, diameter: 36, center: CGPoint(x: 15, y: 22), scale: 0.11)
            Text(row.name)
                .font(.nunito(16, .black, relativeTo: .body))
                .frame(maxWidth: .infinity, alignment: .leading)
            switch row.status {
            case .there:
                CoverChip(text: "There", fill: Theme.signalSoft, foreground: Theme.okText)
            case .late:
                CoverChip(text: "Running late", fill: Theme.dangerSoft, foreground: Theme.lateText)
            case .notComing:
                CoverChip(text: "Can't make it", fill: Theme.pendingFill, foreground: Theme.inkSecondary)
            case .away(let minutes):
                Text("\(minutes) min away")
                    .font(.nunito(14, .heavy, relativeTo: .subheadline))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    // MARK: Your answer

    private var rsvpRow: some View {
        MeetupFlexRow(spacing: 8) {
            ForEach(MeetupRSVP.allCases) { choice in
                rsvpButton(choice)
            }
        }
    }

    private func rsvpButton(_ choice: MeetupRSVP) -> some View {
        let selected = rsvp == choice
        return Button {
            rsvp = choice
            // TODO: send the RSVP to the flock through ChirpCore.
        } label: {
            Text(choice.rawValue)
                .font(.nunito(14, .black, relativeTo: .subheadline))
                .foregroundStyle(selected ? BirdRenderer.ink : Theme.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    if selected {
                        // The file's `inset 0 -3px 0 #F2A100` under a sun fill.
                        ZStack(alignment: .top) {
                            Capsule().fill(Theme.sunDeep)
                            Capsule().fill(Theme.sun).padding(.bottom, 3)
                        }
                        .clipShape(Capsule())
                    } else {
                        Capsule().fill(Theme.card)
                            .overlay(Capsule().strokeBorder(Theme.solid, lineWidth: 2))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The file's `flex: 1 1 auto` row: each button its natural width plus an
/// equal share of what is left; shrinks in proportion when it does not fit.
struct MeetupFlexRow: Layout {
    var spacing: CGFloat

    private func widths(_ total: CGFloat, _ subviews: Subviews) -> [CGFloat] {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }
        let available = total - spacing * CGFloat(max(subviews.count - 1, 0))
        let sum = ideal.reduce(0, +)
        guard sum > 0, !subviews.isEmpty else { return ideal }
        if sum <= available {
            let extra = (available - sum) / CGFloat(subviews.count)
            return ideal.map { $0 + extra }
        }
        return ideal.map { $0 * available / sum }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }
        let total = proposal.width ?? (ideal.reduce(0, +) + spacing * CGFloat(max(subviews.count - 1, 0)))
        let w = widths(total, subviews)
        let height = zip(subviews, w).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let w = widths(bounds.width, subviews)
        var x = bounds.minX
        for (view, width) in zip(subviews, w) {
            view.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                       proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }
}

/// The small arrow in the directions row: `M18 8 L25 25 L18 21 L11 25 Z` in a 36 box.
struct MeetupPointer: Shape {
    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 36
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        var path = Path()
        path.move(to: p(18, 8))
        path.addLine(to: p(25, 25))
        path.addLine(to: p(18, 21))
        path.addLine(to: p(11, 25))
        path.closeSubpath()
        return path
    }
}

/// The 358 x 132 hill scene at the top of the meet-up card: sky, two ranges of
/// hills, the gondola on its cable and the lilac flag, at the file's coordinates.
struct MeetupHillScene: View {
    var body: some View {
        Canvas { ctx, size in
            let k = size.width / 358
            ctx.scaleBy(x: k, y: k)
            ctx.fill(Path(CGRect(x: 0, y: 0, width: 358, height: 132)),
                     with: .linearGradient(Gradient(colors: [Theme.hillTop, Theme.hillBottom]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: 132)))
            ctx.fill(Self.polygon([(0, 132), (0, 92), (70, 54), (120, 80), (190, 30), (260, 74), (310, 48),
                                   (358, 70), (358, 132)]),
                     with: .color(Theme.farHills.opacity(0.75)))
            ctx.fill(Self.polygon([(0, 132), (0, 108), (90, 84), (170, 102), (250, 86), (358, 104), (358, 132)]),
                     with: .color(Theme.card))
            var cable = Path()
            cable.move(to: CGPoint(x: 60, y: 40)); cable.addLine(to: CGPoint(x: 300, y: 96))
            ctx.stroke(cable, with: .color(Theme.ink.opacity(0.6)), lineWidth: 2)

            // Gondola, translate(180 68)
            var g = ctx
            g.translateBy(x: 180, y: 68)
            var hanger = Path()
            hanger.move(to: .zero); hanger.addLine(to: CGPoint(x: 0, y: -6))
            g.stroke(hanger, with: .color(Theme.ink), lineWidth: 2)
            g.fill(Path(roundedRect: CGRect(x: -16, y: -6, width: 32, height: 24), cornerRadius: 6),
                   with: .color(Theme.gondola))
            g.fill(Path(roundedRect: CGRect(x: -11, y: -1, width: 9, height: 8), cornerRadius: 2),
                   with: .color(Theme.gondolaWindow))
            g.fill(Path(roundedRect: CGRect(x: 2, y: -1, width: 9, height: 8), cornerRadius: 2),
                   with: .color(Theme.gondolaWindow))

            // Flag, translate(296 84)
            var f = ctx
            f.translateBy(x: 296, y: 84)
            var pole = Path()
            pole.move(to: CGPoint(x: 0, y: 26)); pole.addLine(to: CGPoint(x: 0, y: -14))
            f.stroke(pole, with: .color(Theme.ink), style: .init(lineWidth: 3, lineCap: .round))
            f.fill(Self.polygon([(0, -14), (26, -6), (0, 2)]), with: .color(Theme.flag))
        }
        .aspectRatio(358.0 / 132.0, contentMode: .fit)
    }

    static func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: CGPoint(x: first.0, y: first.1))
        for pt in points.dropFirst() { p.addLine(to: CGPoint(x: pt.0, y: pt.1)) }
        p.closeSubpath()
        return p
    }
}

/// Meetup's demo content, as `Meetup.dc.html` shows it.
enum MeetupDemo {
    enum Status: Equatable { case there, away(minutes: Int), late, notComing }

    struct Row: Identifiable {
        var id: String
        var name: String
        var palette: BirdPalette
        var status: Status
    }

    static let setBy = Flock.jon
    static let place = "Bottom of the blue gondola"
    static let when = "3:30 PM · in 25 min"
    static let distance = "420 m, downhill"
    static let travel = "About 6 min on skis"

    static func rows(you: Person, yourAnswer: MeetupRSVP) -> [Row] {
        let yourStatus: Status
        switch yourAnswer {
        case .onMyWay: yourStatus = .away(minutes: 6)
        case .runningLate: yourStatus = .late
        case .cantMakeIt: yourStatus = .notComing
        }
        return [
            Row(id: Flock.jon.id, name: Flock.jon.name, palette: Flock.jon.palette, status: .there),
            Row(id: Flock.maya.id, name: Flock.maya.name, palette: Flock.maya.palette, status: .away(minutes: 3)),
            Row(id: you.id, name: "You", palette: you.palette, status: yourStatus),
            Row(id: Flock.priya.id, name: Flock.priya.name, palette: Flock.priya.palette, status: .late),
        ]
    }
}
