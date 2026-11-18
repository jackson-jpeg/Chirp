import ChirpCore
import SwiftUI

/// Why Big Birdhouse's sheet opened, so it can say so in one line.
enum BigBirdhouseReason: Hashable, Identifiable {
    /// The starter of a full free birdhouse tapped Invite friends.
    case invite
    /// Talk's card: the birdhouse grew past the free size anyway.
    case grew(birds: Int)
    /// A locked color or chirp in Make your bird.
    case bird
    /// Talk's birdhouse menu.
    case menu
    var id: Self { self }
}

/// Big Birdhouse, the one purchase (ChirpCore `BigBirdhouse`, `Store`): what it adds,
/// the price from the App Store, Restore, and Not now. Nothing is cut off by
/// saying Not now, and friends who join never see this.
struct BigBirdhouseView: View {
    let reason: BigBirdhouseReason
    @Environment(Store.self) private var store
    @Environment(Mesh.self) private var mesh
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(text: "Big Birdhouse")
                Text(headline)
                    .font(.pageTitle)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 10) {
                    line("person.3", "Birdhouses you start grow past \(BigBirdhouse.freeBirds) birds")
                    line("paintpalette", "Every bird color and every chirp")
                    line("gift", "Friends who join your birdhouse never pay")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                if store.unlocked {
                    Text("Big Birdhouse is yours. Thank you!")
                        .font(.nunito(17, .black, relativeTo: .headline))
                        .foregroundStyle(Theme.signalText)
                        .accessibilityIdentifier("bigBirdhouse.owned")
                    if reason == .invite, let channel = mesh.birdhouseChannel, let link = BirdhouseInvite.link(for: channel) {
                        ShareLink(item: link,
                                  subject: Text("Join \(channel.name) on ChirpChirps"),
                                  message: Text("Join my birdhouse on ChirpChirps, so we can talk with no signal. Open this link on your iPhone.")) {
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
                        .accessibilityIdentifier("bigBirdhouse.buy")
                    Text("One purchase, yours for good. No subscription.")
                        .font(.meta)
                        .foregroundStyle(Theme.inkSecondary)
                    HStack {
                        Button("Restore purchase") { Task { await store.restore() } }
                            .disabled(busy)
                            .accessibilityIdentifier("bigBirdhouse.restore")
                        Spacer()
                        Button("Not now") { dismiss() }
                            .accessibilityIdentifier("bigBirdhouse.notNow")
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
        case .invite: "Your birdhouse has \(BigBirdhouse.freeBirds) birds. Big Birdhouse lets it grow."
        case .grew(let n): "Your birdhouse has \(n) birds. Big Birdhouse lets it grow."
        case .bird: "More colors and chirps come with Big Birdhouse."
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
        if let price = store.product?.displayPrice { return "Get Big Birdhouse for \(price)" }
        return "Get Big Birdhouse"
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
