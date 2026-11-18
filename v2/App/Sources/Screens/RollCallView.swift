import ChirpCore
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
    @Environment(Mesh.self) private var mesh
    /// Screenshot runs only: the design's answer, kept on this screen.
    @State private var answer: RollCallAnswer = .notYet

    /// Real use, or the demo flock (even in a UI test launched with `-screen`).
    private var live: Bool { !router.screenshotRun || mesh.inDemo }
    private var me: PeerID { mesh.dispatch.me }
    private var board: RollCallBoard { mesh.rollCalls }

    /// Your answer: the board's in real use, this screen's in screenshot runs.
    private var yourAnswer: RollCallAnswer {
        guard live else { return answer }
        if board.help[me] != nil { return .needHelp }
        switch board.status(of: me) {
        case .ok(let at): return board.ask == nil ? .notYet : .ok(at: at)
        case .needsHelp: return .needHelp
        case .noAnswer: return .notYet
        }
    }

    private var eyebrow: String {
        guard live else { return RollCallDemo.eyebrow }
        guard let ask = board.ask else { return "\(flock.displayName) · No roll call yet" }
        let who = ask.from == me ? "You" : (name(of: ask.from) ?? "Someone")
        let mins = max(0, Int(Date.now.timeIntervalSince(ask.at) / 60))
        return "\(flock.displayName) · \(who) asked " + (mins == 0 ? "just now" : "\(mins) min ago")
    }

    private func name(of peer: PeerID) -> String? {
        flock.others.first { $0.peer == peer }?.name ?? mesh.dispatch.roster.person(peer)?.name
    }

    private var tiles: [RollCallDemo.Tile] {
        guard live else { return RollCallDemo.tiles(you: flock.you, yourAnswer: answer) }
        let friends = mesh.dispatch.friends
        let heard = board.heardFrom
        let people = flock.others.filter { $0.peer.map { friends.contains($0) || heard.contains($0) } ?? false }
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        var out = people.map { p -> RollCallDemo.Tile in
            let status: RollCallDemo.Status
            if let peer = p.peer, board.help[peer] != nil {
                status = .help
            } else {
                switch p.peer.map(board.status(of:)) ?? .noAnswer {
                case .ok(let at): status = .ok(f.string(from: at))
                case .needsHelp: status = .help
                case .noAnswer: status = .noAnswer
                }
            }
            return RollCallDemo.Tile(id: p.id, name: p.name, palette: p.palette, status: status)
        }
        let mine: RollCallDemo.Status
        switch yourAnswer {
        case .needHelp: mine = .help
        case .ok(let at): mine = .ok(f.string(from: at))
        case .notYet: mine = board.waitingOn(me) ? .yourTurn : .noAnswer
        }
        out.append(RollCallDemo.Tile(id: flock.you.id, name: "You", palette: flock.you.palette, status: mine, isYou: true))
        return out
    }

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
                Text(eyebrow.uppercased())
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
                .lineHeight(.multiple(factor: 1.1))   // the design's line-height
                .tracking(-0.34)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: Tiles

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(tiles) { tile in
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
            if let line = noteLine { Text(line) }
            if yourAnswer == .needHelp {
                Text("Everyone on \(flock.displayName) who is close by can see you asked for help.")
                    .foregroundStyle(Theme.danger)
            }
        }
        .font(.nunito(15, .bold, relativeTo: .subheadline))
        .lineSpacing(1.5)
        .foregroundStyle(Theme.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Buttons

    /// The design's note in screenshot runs; in real use, who asked for help.
    private var noteLine: String? {
        guard live else { return RollCallDemo.note }
        let asking = board.needingHelp(except: me).compactMap(name(of:))
        if !asking.isEmpty {
            return asking.count == 1 ? "\(asking[0]) asked for help." : "\(asking.joined(separator: ", ")) asked for help."
        }
        if board.ask == nil { return "Ask everyone on \(flock.displayName) if they are OK. Answers come in as their phones hear it." }
        return "Answers come in as each phone hears the roll call."
    }

    private var isOK: Bool {
        if case .ok = yourAnswer { return true }
        return false
    }

    /// No roll call to answer (or it is yours): the first button asks everyone.
    private var asks: Bool { live && (board.ask == nil || board.ask?.from == me) }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button {
                if !live { answer = .ok(at: .now) }
                else if asks { mesh.startRollCall() }
                else { mesh.answerRollCall(ok: true) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: asks ? "person.3.fill" : "checkmark")
                        .font(.system(size: 18, weight: .black))
                    Text(asks ? (board.ask == nil ? "Ask everyone" : "Ask again")
                         : (isOK ? "Sent: I'm OK" : "I'm OK"))
                }
                .font(.nunito(19, .black, relativeTo: .headline))
                .foregroundStyle(isOK && !asks ? Theme.signal : Theme.onSolid)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(isOK && !asks ? Theme.signalSoft : Theme.solid, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled((isOK && !asks) || (live && mesh.rollCallChannel == nil))
            .accessibilityIdentifier("rollCall.primary")

            Button {
                if !live { answer = answer == .needHelp ? .notYet : .needHelp }
                else if yourAnswer == .needHelp { mesh.cancelHelp() }
                else { mesh.askForHelp() }
            } label: {
                Text(yourAnswer == .needHelp ? "Help asked. Tap to cancel" : "I need help")
                    .font(.nunito(17, .black, relativeTo: .headline))
                    .foregroundStyle(yourAnswer == .needHelp ? Theme.onSolid : Theme.danger)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(yourAnswer == .needHelp ? Theme.danger : Theme.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.danger, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .disabled(live && mesh.rollCallChannel == nil)
            .accessibilityIdentifier("rollCall.help")
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
