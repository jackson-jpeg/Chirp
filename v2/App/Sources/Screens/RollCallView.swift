import SwiftUI

/// Your own answer to a roll call.
enum RollCallAnswer: Equatable {
    case notYet
    case ok(at: Date)
    case needHelp
}

/// Roll call: "everyone OK?", each person's answer, and yours. Built to
/// `v2/design/RollCall.dc.html`.
struct RollCallView: View {
    @Environment(Router.self) private var router
    @Environment(Flock.self) private var flock
    @State private var answer: RollCallAnswer = .notYet

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 9)
                    grid
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                    note
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                        .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            buttons
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
        }
        .foregroundStyle(Theme.ink)
        .screenBackground()
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                Text(RollCallDemo.eyebrow.uppercased())
                    .font(.nunito(13, .black, relativeTo: .caption))
                    .tracking(1.3)
                    .foregroundStyle(Theme.inkSecondary)
                Spacer(minLength: 8)
                // The design shows no close control; this one sits on the
                // eyebrow's line so the layout below is unchanged.
                CoverCloseButton(label: "Close roll call") { router.overlay = nil }
                    .padding(.vertical, -13)
            }
            Text("Roll call: everyone OK?")
                .font(.nunito(34, .black, relativeTo: .largeTitle))
                .tracking(-0.34)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: Tiles

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(RollCallDemo.tiles(you: flock.you, yourAnswer: answer)) { tile in
                tileView(tile)
            }
        }
    }

    private func tileView(_ tile: RollCallDemo.Tile) -> some View {
        VStack(spacing: 6) {
            CoverBirdCanvas(palette: tile.palette, size: CGSize(width: 84, height: 70),
                            center: CGPoint(x: 42, y: 34), scale: 0.22)
                .opacity(tile.status == .noAnswer ? 0.5 : 1)
            Text(tile.name)
                .font(.nunito(16, .black, relativeTo: .body))
            chip(tile.status)
        }
        .multilineTextAlignment(.center)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            if let ring = ring(tile) {
                RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(ring, lineWidth: 3)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func ring(_ tile: RollCallDemo.Tile) -> Color? {
        guard tile.isYou else { return nil }
        switch tile.status {
        case .yourTurn: return Theme.sun
        case .help: return Theme.danger
        default: return nil
        }
    }

    @ViewBuilder
    private func chip(_ status: RollCallDemo.Status) -> some View {
        switch status {
        case .ok(let time):
            CoverChip(text: "OK · \(time)", fill: Theme.signalSoft, foreground: Theme.okText,
                      verticalPadding: 3, cornerRadius: 10)
        case .noAnswer:
            CoverChip(text: "No answer yet", fill: Theme.pendingFill, foreground: Theme.inkSecondary,
                      verticalPadding: 3, cornerRadius: 10)
        case .yourTurn:
            CoverChip(text: "Your turn", fill: Theme.sunGlow, foreground: Theme.turnText,
                      verticalPadding: 3, cornerRadius: 10)
        case .help:
            CoverChip(text: "Needs help", fill: Theme.dangerSoft, foreground: Theme.danger,
                      verticalPadding: 3, cornerRadius: 10)
        }
    }

    // MARK: Note

    private var note: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(RollCallDemo.note)
            if answer == .needHelp {
                Text("Everyone on \(flock.flockName) can see you asked for help, and where you were last heard.")
                    .foregroundStyle(Theme.danger)
            }
        }
        .font(.nunito(15, .bold, relativeTo: .subheadline))
        .lineSpacing(1.5)
        .foregroundStyle(Theme.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Buttons

    private var isOK: Bool {
        if case .ok = answer { return true }
        return false
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button {
                answer = .ok(at: .now)
                // TODO: send the roll call answer (OK) through ChirpCore.
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .black))
                    Text(isOK ? "Sent: I'm OK" : "I'm OK")
                }
                .font(.nunito(19, .black, relativeTo: .headline))
                .foregroundStyle(isOK ? Theme.signal : Theme.onSolid)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(isOK ? Theme.signalSoft : Theme.solid, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isOK)

            Button {
                answer = answer == .needHelp ? .notYet : .needHelp
                // TODO: send (or cancel) the help call through ChirpCore; it
                // goes to everyone in range with your last known place.
            } label: {
                Text(answer == .needHelp ? "Help asked. Tap to cancel" : "I need help")
                    .font(.nunito(17, .black, relativeTo: .headline))
                    .foregroundStyle(answer == .needHelp ? Theme.onSolid : Theme.danger)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(answer == .needHelp ? Theme.danger : Theme.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.danger, lineWidth: 2))
            }
            .buttonStyle(.plain)
        }
    }
}

/// Roll call's demo content, as `RollCall.dc.html` shows it.
enum RollCallDemo {
    enum Status: Equatable { case ok(String), noAnswer, yourTurn, help }

    struct Tile: Identifiable {
        var id: String
        var name: String
        var palette: BirdPalette
        var status: Status
        var isYou = false
    }

    static let eyebrow = "Ski trip · Jon asked 1 min ago"
    static let note = "Priya was last heard at 10:04, 640 m downhill, through Jon's phone. We'll keep asking her phone every minute."

    static func tiles(you: Person, yourAnswer: RollCallAnswer) -> [Tile] {
        let yours: Status
        switch yourAnswer {
        case .notYet: yours = .yourTurn
        case .ok(let at):
            let f = DateFormatter()
            f.dateFormat = "h:mm"
            yours = .ok(f.string(from: at))
        case .needHelp: yours = .help
        }
        return [
            Tile(id: Flock.jon.id, name: Flock.jon.name, palette: Flock.jon.palette, status: .ok("10:12")),
            Tile(id: Flock.maya.id, name: Flock.maya.name, palette: Flock.maya.palette, status: .ok("10:12")),
            Tile(id: Flock.priya.id, name: Flock.priya.name, palette: Flock.priya.palette, status: .noAnswer),
            Tile(id: you.id, name: "You", palette: you.palette, status: yours, isYou: true),
        ]
    }
}
