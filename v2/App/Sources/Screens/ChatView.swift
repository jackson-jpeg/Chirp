import SwiftUI

/// Chat, built to `v2/design/Chat.dc.html`: the flock's written and voice
/// messages, with a composer above the tab bar (MainTabs draws the bar).
struct ChatView: View {
    @Environment(Flock.self) private var flock
    @State private var items: [ChatItem] = ChatItem.demo()

    /// Messages from people you blocked are never shown (App Review 5.1.2(i)).
    private var visibleItems: [ChatItem] {
        items.filter { item in
            if case .message(let m) = item, case .person(let p) = m.sender { return !flock.isBlocked(p.id) }
            return true
        }
    }
    @State private var draft = ""
    @State private var recordingSince: Date?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    let items = visibleItems
                    if items.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(items) { item in
                                row(item).id(item.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: items.count) {
                    guard let last = items.last?.id else { return }
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
            composer
        }
        .screenBackground()
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Chat")
                .font(.nunito(34, .black, relativeTo: .largeTitle))
                .tracking(-0.34)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text("\(flock.flockName) · works with no signal")
                .font(.meta)
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        // The file's 56 pt top padding, less the 47 pt status bar inset of a 390 x 844 phone.
        .padding(.top, 9)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No messages yet")
                .font(.cardTitle)
                .foregroundStyle(Theme.ink)
            Text("Say hi to the flock. Messages get through even with no signal.")
                .font(.meta)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 120)
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ item: ChatItem) -> some View {
        switch item {
        case .event(_, let text):
            Text(text)
                .font(.nunito(13, .heavy, relativeTo: .footnote))
                .foregroundStyle(Theme.inkBody)
                .padding(.vertical, 4)
                .padding(.horizontal, 12)
                .background(Theme.eventPill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: .infinity)
        case .message(let m):
            switch m.sender {
            case .person(let p): ChatIncomingRow(message: m, person: p)
            case .you: ChatOutgoingRow(message: m, othersCount: flock.others.count)
            }
        }
    }

    // MARK: Composer

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var composer: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                TextField("", text: $draft,
                          prompt: Text("Message the flock").foregroundStyle(Theme.placeholder))
                    .font(.nunito(16, .bold, relativeTo: .body))
                    .foregroundStyle(Theme.ink)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .focused($fieldFocused)
                    .accessibilityLabel("Message")
                    .opacity(recordingSince == nil ? 1 : 0)
                if recordingSince != nil {
                    Text("Recording. Let go to send.")
                        .font(.nunito(16, .heavy, relativeTo: .body))
                        .foregroundStyle(Theme.ink)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.field, in: Capsule())

            if trimmedDraft.isEmpty {
                micButton
            } else {
                Button(action: send) {
                    ZStack {
                        ChatSunFill(shape: Circle())
                        ChatIcon.arrowUp
                            .stroke(Theme.navy, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                            .frame(width: 22, height: 22)
                    }
                    .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send")
            }
        }
        .padding(.vertical, 10)
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .background(Theme.card)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    /// "Hold to send a voice message": hold to record, let go to send.
    private var micButton: some View {
        let recording = recordingSince != nil
        return ZStack {
            ChatSunFill(shape: Circle(),
                        top: recording ? Theme.coral : Theme.sun,
                        lip: recording ? Theme.coralHot : Theme.sunDeep)
            ChatIcon.mic
                .stroke(Theme.navy, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                .frame(width: 22, height: 22)
        }
        .frame(width: 48, height: 48)
        .scaleEffect(recording ? 1.08 : 1)
        .animation(.easeOut(duration: 0.15), value: recording)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if recordingSince == nil { recordingSince = .now }
                }
                .onEnded { _ in
                    guard let start = recordingSince else { return }
                    recordingSince = nil
                    let held = Date.now.timeIntervalSince(start)
                    if held >= 0.4 { sendVoice(seconds: max(1, Int(held.rounded()))) }
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Hold to send a voice message")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { sendVoice(seconds: 3) }
    }

    private func send() {
        let text = trimmedDraft
        guard !text.isEmpty else { return }
        items.append(.message(ChatMessage(sender: .you, kind: .text(text), status: .sent)))
        draft = ""
    }

    private func sendVoice(seconds: Int) {
        items.append(.message(ChatMessage(
            sender: .you,
            kind: .voice(seconds: seconds, caption: nil, bars: ChatItem.bars(forSeconds: seconds), played: 0),
            status: .sent)))
    }
}

// MARK: - Incoming

/// Someone else's message: their bird at the bubble's foot, a white bubble
/// with a small bottom-left corner, their name in their color.
struct ChatIncomingRow: View {
    var message: ChatMessage
    var person: Person

    private static let bubble = UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 6,
                                                       bottomTrailingRadius: 20, topTrailingRadius: 20,
                                                       style: .continuous)

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ChatWellAvatar(palette: person.palette, size: 36, origin: CGPoint(x: 15, y: 22), scale: 0.12)
            content
                .background(Theme.card, in: Self.bubble)
                // max-width 270 plus 14 + 14 padding, as the file's content-box does.
                .frame(maxWidth: 298, alignment: .leading)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch message.kind {
        case .text(let text):
            VStack(alignment: .leading, spacing: 2) {
                name
                Text(text)
                    .font(.nunito(16, .bold, relativeTo: .body))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .accessibilityElement(children: .combine)
        case .voice(let seconds, let caption, let bars, let played):
            VStack(alignment: .leading, spacing: 8) {
                name
                ChatVoicePlayer(owner: "\(person.name)'s", seconds: seconds, bars: bars, initiallyPlayed: played, onSun: false)
                if let caption {
                    Text(caption)
                        .font(.nunito(15, .bold, relativeTo: .body))
                        .lineSpacing(0.5)
                        .foregroundStyle(Theme.inkBody)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // The waveform row stretches, so a voice bubble fills its 298 max
            // as in the design (the frame below caps it), not the caption's width.
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .accessibilityElement(children: .contain)
        }
    }

    private var name: some View {
        Text(person.name)
            .font(.nunito(13, .black, relativeTo: .footnote))
            .foregroundStyle(Theme.nameColor(person.palette))
    }
}

// MARK: - Yours

/// Your message: a sun bubble on the right with a small bottom-right corner,
/// and under it who has heard it.
struct ChatOutgoingRow: View {
    var message: ChatMessage
    var othersCount: Int

    private static let bubble = UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20,
                                                       bottomTrailingRadius: 6, topTrailingRadius: 20,
                                                       style: .continuous)

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            content
                .background { ChatSunFill(shape: Self.bubble) }
                // max-width 260 plus 14 + 14 padding.
                .frame(maxWidth: 288, alignment: .trailing)
            if let status = message.status { statusLine(status) }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private var content: some View {
        switch message.kind {
        case .text(let text):
            Text(text)
                .font(.nunito(16, .heavy, relativeTo: .body))
                .foregroundStyle(Theme.navy)   // ink on sun in both schemes
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .accessibilityLabel("You: \(text)")
        case .voice(let seconds, let caption, let bars, let played):
            VStack(alignment: .leading, spacing: 8) {
                ChatVoicePlayer(owner: "your", seconds: seconds, bars: bars, initiallyPlayed: played, onSun: true)
                if let caption {
                    Text(caption)
                        .font(.nunito(15, .bold, relativeTo: .body))
                        .foregroundStyle(Theme.navy)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
        }
    }

    @ViewBuilder
    private func statusLine(_ status: ChatMessage.Status) -> some View {
        switch status {
        case .sent:
            HStack(spacing: 4) {
                ChatTicks(double: false)
                    .stroke(Theme.inkSecondary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(width: 16, height: 12)
                Text("Sent")
            }
            .font(.nunito(12, .heavy, relativeTo: .caption))
            .foregroundStyle(Theme.inkSecondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sent, not heard yet")
        case .heardBy(let people):
            let all = people.count == othersCount && people.count > 1
            HStack(spacing: 4) {
                ChatTicks(double: true)
                    .stroke(Theme.signalText, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(width: 16, height: 12)
                Text(all ? "Heard by all \(people.count)" : "Heard by \(TalkText.list(people.map(\.name)))")
            }
            .font(.nunito(12, .heavy, relativeTo: .caption))
            .foregroundStyle(Theme.inkSecondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Heard by \(TalkText.list(people.map(\.name)))")
        }
    }
}

/// The file's ticks, `M1 6l3 3 6-7M6 9l1 1 7-8` in a 16 x 12 box.
struct ChatTicks: Shape {
    var double: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 1, y: 6)); p.addLine(to: CGPoint(x: 4, y: 9)); p.addLine(to: CGPoint(x: 10, y: 2))
        if double {
            p.move(to: CGPoint(x: 6, y: 9)); p.addLine(to: CGPoint(x: 7, y: 10)); p.addLine(to: CGPoint(x: 14, y: 2))
        }
        return p.applying(CGAffineTransform(a: rect.width / 16, b: 0, c: 0, d: rect.height / 12,
                                            tx: rect.minX, ty: rect.minY))
    }
}

// MARK: - Voice message

/// Play button, waveform and length. Playing walks the played bars along.
struct ChatVoicePlayer: View {
    var owner: String
    var seconds: Int
    var bars: [CGFloat]
    var initiallyPlayed: Int
    var onSun: Bool

    @State private var playing = false
    @State private var played: Int?

    private var shownPlayed: Int { played ?? initiallyPlayed }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if !playing, shownPlayed >= bars.count { played = 0 }
                playing.toggle()
            } label: {
                ZStack {
                    Circle().fill(onSun ? Color.white : Theme.sun)
                    if playing {
                        HStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 1).frame(width: 3.5, height: 11)
                            RoundedRectangle(cornerRadius: 1).frame(width: 3.5, height: 11)
                        }
                        .foregroundStyle(Theme.navy)
                    } else {
                        ChatPlayTriangle()
                            .fill(Theme.navy)
                            .frame(width: 14, height: 14)
                    }
                }
                .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playing ? "Pause \(owner) message" : "Play \(owner) message")

            HStack(spacing: 4) {
                ForEach(bars.indices, id: \.self) { i in
                    Capsule()
                        .fill(i < shownPlayed ? playedColor : restColor)
                        .frame(width: 4, height: bars[i])
                }
            }
            .frame(width: 150, height: 24, alignment: .leading)
            .accessibilityHidden(true)

            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                .font(.nunito(13, .heavy, relativeTo: .footnote))
                .foregroundStyle(onSun ? Theme.navy : Theme.inkSecondary)
                .accessibilityLabel("\(seconds) seconds")
        }
        .task(id: playing) {
            guard playing else { return }
            let step = Double(max(seconds, 1)) / Double(max(bars.count, 1))
            while shownPlayed < bars.count {
                try? await Task.sleep(for: .seconds(step))
                if Task.isCancelled { return }
                played = shownPlayed + 1
            }
            playing = false
        }
    }

    private var playedColor: Color { onSun ? Theme.navy : Theme.ink }
    private var restColor: Color { onSun ? Theme.sunDeep : Theme.waveRest }
}

/// `M3 1.5 L12 7 L3 12.5 Z` in a 14 pt box.
struct ChatPlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 14
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + 3 * k, y: rect.minY + 1.5 * k))
        p.addLine(to: CGPoint(x: rect.minX + 12 * k, y: rect.minY + 7 * k))
        p.addLine(to: CGPoint(x: rect.minX + 3 * k, y: rect.minY + 12.5 * k))
        p.closeSubpath()
        return p
    }
}
