import ActivityKit
import ChirpCore
import SwiftUI
import WidgetKit

/// The `ChirpLive` widget extension: only the Live Activity (no home screen
/// widgets). Drawn from `v2/design/source/LockScreen.dc.html`, with one change
/// on purpose: the design's "Hold" button is "Talk" and opens the app, because
/// talking works only with the app open (Jackson's option 1).
@main
struct ChirpLiveBundle: WidgetBundle {
    var body: some Widget { ChirpLiveActivity() }
}

struct ChirpLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChirpActivity.self) { context in
            LockScreenCard(card: context.state)
                .activityBackgroundTint(Color.hex(0xFAFCFF, opacity: 0.92))
                .activitySystemActionForegroundColor(Color.hex(0x14233F))
                .widgetURL(ChirpLinks.talk)
        } dynamicIsland: { context in
            let card = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Avatar(card: card, size: 44)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.headline).font(.nunito(17, .black)).foregroundStyle(.white).lineLimit(1)
                        if let line = card.line {
                            Text(line).font(.nunito(14, .bold)).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
                        } else {
                            Text("\(card.flock) \u{00B7} \(card.count)").font(.nunito(14, .bold)).foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TalkButton(size: 52)
                }
            } compactLeading: {
                Avatar(card: card, size: 24)
            } compactTrailing: {
                if card.talking {
                    Wave().frame(width: 34, height: 14)
                } else {
                    Text(card.speaker ?? card.flock).font(.nunito(13, .black)).foregroundStyle(.white).lineLimit(1)
                }
            } minimal: {
                Avatar(card: card, size: 24)
            }
            .widgetURL(ChirpLinks.talk)
        }
    }
}

/// The card on the Lock Screen: flock and count, the last speaker's bird,
/// their words, and the Talk button.
struct LockScreenCard: View {
    let card: LiveCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(Theme.sun).frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.hex(0xFFF1C2), lineWidth: 3))
                Text(card.flock).font(.nunito(13, .black))
                Text("\u{00B7} \(card.count)").font(.nunito(13, .bold)).foregroundStyle(Color.hex(0x3D5170))
            }
            HStack(spacing: 12) {
                Avatar(card: card, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.speaker == nil ? "No one has talked yet" : card.headline)
                        .font(.nunito(17, .black))
                    if let line = card.line {
                        Text("\u{201C}\(line)\u{201D}").font(.nunito(15, .bold)).foregroundStyle(Color.hex(0x2B3D5C)).lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                TalkButton(size: 64)
            }
        }
        .foregroundStyle(Color.hex(0x14233F))
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .accessibilityElement(children: .combine)
    }
}

/// The speaker's bird in its round well, beak open while they talk; the
/// flock's sun before anyone has spoken.
struct Avatar: View {
    let card: LiveCard
    let size: CGFloat

    var body: some View {
        let palette = BirdPalette.all[Int(card.palette) % BirdPalette.all.count]
        ZStack {
            Circle().fill(card.speaker == nil ? Color.hex(0xFFF1C2) : Theme.well(palette))
            if card.speaker != nil {
                BirdView(palette: palette, talking: card.talking).padding(size * 0.14)
            } else {
                Circle().fill(Theme.sun).padding(size * 0.28)
            }
        }
        .frame(width: size, height: size)
        .environment(\.colorScheme, .light)
    }
}

/// Opens the app on Talk. Not a hold-to-talk: nothing talks while locked.
struct TalkButton: View {
    let size: CGFloat

    var body: some View {
        Link(destination: ChirpLinks.talk) {
            VStack(spacing: 1) {
                Image(systemName: "mic.fill").font(.system(size: size * 0.32, weight: .bold))
                Text("Talk").font(.nunito(size * 0.17, .black))
            }
            .foregroundStyle(Color.hex(0x14233F))
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.sun))
            .overlay(Circle().stroke(Theme.sunDeep, lineWidth: 2))
        }
        .accessibilityLabel("Open ChirpChirps to talk")
    }
}

/// The yellow bars beside a talking name in the Dynamic Island.
struct Wave: View {
    var body: some View {
        HStack(spacing: 3) {
            ForEach([4.0, 10, 16, 8, 14, 6], id: \.self) { h in
                Capsule().fill(Theme.sun).frame(width: 3, height: h)
            }
        }
    }
}
