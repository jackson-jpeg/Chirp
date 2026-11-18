import ChirpCore
import SwiftUI

/// Why Big Flock's sheet opened, so it can say so in one line.
enum BigFlockReason: Hashable, Identifiable {
    /// The starter of a full free flock tapped Invite friends.
    case invite
    /// Talk's card: the flock grew past the free size anyway.
    case grew(birds: Int)
    /// A locked color or chirp in Make your bird.
    case bird
    /// Talk's flock menu.
    case menu
    var id: Self { self }
}

/// Big Flock, the one purchase (ChirpCore `BigFlock`, `Store`): what it adds,
/// the price from the App Store, Restore, and Not now. Nothing is cut off by
/// saying Not now, and friends who join never see this.
struct BigFlockView: View {
    let reason: BigFlockReason
    @Environment(Store.self) private var store
    @Environment(Mesh.self) private var mesh
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(text: "Big Flock")
                Text(headline)
                    .font(.pageTitle)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 10) {
                    line("person.3", "Flocks you start grow past \(BigFlock.freeBirds) birds")
                    line("paintpalette", "Every bird color and every chirp")
                    line("gift", "Friends who join your flock never pay")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                if store.unlocked {
                    Text("Big Flock is yours. Thank you!")
                        .font(.nunito(17, .black, relativeTo: .headline))
                        .foregroundStyle(Theme.signalText)
                        .accessibilityIdentifier("bigFlock.owned")
                    if reason == .invite, let channel = mesh.flockChannel, let link = FlockInvite.link(for: channel) {
                        ShareLink(item: link,
                                  subject: Text("Join \(channel.name) on ChirpChirps"),
                                  message: Text("Join my flock on ChirpChirps, so we can talk with no signal. Open this link on your iPhone.")) {
                            Text("Invite friends")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    Button("Done") { dismiss() }
                        .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button(buyTitle) { Task { await store.buy() } }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(busy)
                        .accessibilityIdentifier("bigFlock.buy")
                    Text("One purchase, yours for good. No subscription.")
                        .font(.meta)
                        .foregroundStyle(Theme.inkSecondary)
                    HStack {
                        Button("Restore purchase") { Task { await store.restore() } }
                            .disabled(busy)
                            .accessibilityIdentifier("bigFlock.restore")
                        Spacer()
                        Button("Not now") { dismiss() }
                            .accessibilityIdentifier("bigFlock.notNow")
                    }
                    .font(.nunito(15, .black, relativeTo: .subheadline))
                    .foregroundStyle(Theme.link)
                    .frame(minHeight: 44)
                    if case .failed(let words) = store.status {
                        Text(words)
                            .font(.meta)
                            .foregroundStyle(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(20)
        }
        .screenBackground()
        .task { await store.loadProduct() }
    }

    private var headline: String {
        switch reason {
        case .invite: "Your flock has \(BigFlock.freeBirds) birds. Big Flock lets it grow."
        case .grew(let n): "Your flock has \(n) birds. Big Flock lets it grow."
        case .bird: "More colors and chirps come with Big Flock."
        case .menu: "Bring the whole group."
        }
    }

    private var busy: Bool {
        switch store.status {
        case .loading, .purchasing, .restoring: true
        default: false
        }
    }

    private var buyTitle: String {
        if store.status == .purchasing { return "Buying\u{2026}" }
        if let price = store.product?.displayPrice { return "Get Big Flock for \(price)" }
        return "Get Big Flock"
    }

    private func line(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
                .font(.nunito(16, .bold, relativeTo: .body))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.ink)
        }
    }
}
