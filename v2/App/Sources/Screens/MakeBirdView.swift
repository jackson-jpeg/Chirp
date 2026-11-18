import ChirpCore
import SwiftUI

/// Make your bird (`v2/design/MakeBird`): your bird on the wire in the colors
/// you pick, your name, your feathers and your chirp, then onto the line.
struct MakeBirdView: View {
    /// Opened again from Talk's "You and settings" (a sheet): "Done" instead
    /// of "Hop on the line".
    var editing = false
    @Environment(Flock.self) private var flock
    @Environment(Router.self) private var router
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    /// Its own sheet: Make your bird may itself be a sheet (editing), and one
    /// view cannot present two.
    @State private var bigFlockSheet: BigFlockReason?

    private static let chirps = ChirpSound.names
    private static let maxNameLength = 24

    private var trimmedName: String { flock.you.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canHop: Bool { !trimmedName.isEmpty }

    var body: some View {
        @Bindable var editable = flock
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 9)   // 56 from the top of the screen, under a 47 pt status bar

                SceneCard(cornerRadius: 26) { scene }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                Card(padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                    VStack(alignment: .leading, spacing: 14) {
                        nameField(text: $editable.you.name)
                        feathers
                        chirpPicker
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
            }
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(editing ? "Done" : "Hop on the line", action: hop)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canHop)
                .opacity(canHop ? 1 : 0.4)
                .accessibilityHint(canHop ? Text("") : Text("Type a name first"))
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 6)  // 40 from the screen edge with the 34 pt home indicator
                .background(Theme.morning.ignoresSafeArea())
        }
        .screenBackground()
        .sheet(item: $bigFlockSheet) { reason in
            BigFlockView(reason: reason).presentationDetents([.medium, .large])
        }
        .onChange(of: flock.you.name) { _, new in
            if new.count > Self.maxNameLength { flock.you.name = String(new.prefix(Self.maxNameLength)) }
        }
    }

    // MARK: - Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow(text: eyebrow)
            Text("Make your bird")
                .font(.pageTitle)
                .tracking(-0.32)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var eyebrow: String {
        if editing || flock.flockName.isEmpty { return "Your bird" }
        return router.startedFlock ? "Starting \(flock.flockName)" : "Joining \(flock.flockName)"
    }

    private var scene: some View {
        WireScene(designSize: CGSize(width: 358, height: 200),
                  wire: (start: CGPoint(x: -4, y: 168), control: CGPoint(x: 179, y: 192), end: CGPoint(x: 362, y: 164)),
                  wireWidth: 4,
                  glow: (center: CGPoint(x: 179, y: 70), radius: 140),
                  birds: [SceneBird(palette: flock.you.palette, center: CGPoint(x: 172, y: 126), scale: 0.42)])
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your bird: \(flock.you.palette.name.lowercased())")
            .accessibilityAddTraits(.isImage)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.nunito(14, .black, relativeTo: .subheadline))
            .foregroundStyle(Theme.inkSecondary)
    }

    private func nameField(text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Name")
                .accessibilityHidden(true)
            TextField("Name", text: text, prompt: Text("Your name").foregroundStyle(Theme.inkSecondary))
                .font(.bodyHeavy)
                .foregroundStyle(Theme.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .textContentType(.givenName)
                .submitLabel(.done)
                .focused($nameFocused)
                .onSubmit { nameFocused = false }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 46)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(nameFocused ? Theme.solid : Theme.hairline, lineWidth: 2))
        }
    }

    private var feathers: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Feathers")
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 10) {
                ForEach(BirdPalette.all, id: \.name) { palette in
                    swatch(palette)
                }
            }
        }
    }

    private func swatch(_ palette: BirdPalette) -> some View {
        let selected = flock.you.palette == palette
        // Big Flock colors show with a lock and open its sheet (ChirpCore `BigFlock`).
        let locked = !store.unlocked && !BigFlock.paletteIsFree(palette.index)
        return Button {
            if locked { bigFlockSheet = .bird; return }
            withAnimation(.snappy(duration: 0.2)) { flock.you.palette = palette }
        } label: {
            Circle()
                .fill(palette.swatch)
                .frame(width: 36, height: 36)
                // box-shadow: 0 0 0 3px #FFFFFF, 0 0 0 5px #14233F
                .background {
                    ZStack {
                        Circle().fill(Theme.solid).padding(-5)
                        Circle().fill(Theme.card).padding(-3)
                    }
                    .opacity(selected ? 1 : 0)
                }
                .overlay {
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 1)
                    }
                }
                .contentShape(Circle().inset(by: -5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(locked ? "\(palette.name), comes with Big Flock" : palette.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var chirpPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(Text("Your chirp").font(.nunito(14, .black, relativeTo: .subheadline)))\(Text(" · plays when you start talking").font(.nunito(14, .bold, relativeTo: .subheadline)))")
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { chirpPills }
                VStack(spacing: 8) { chirpPills }
            }
        }
    }

    @ViewBuilder private var chirpPills: some View {
        ForEach(Self.chirps.indices, id: \.self) { i in
            let locked = !store.unlocked && !BigFlock.chirpIsFree(i)
            ChoicePill(title: Self.chirps[i], systemImage: locked ? "lock.fill" : "play.fill", selected: flock.you.chirp == i) {
                // A locked chirp still plays, so you hear what Big Flock adds.
                ChirpPlayer.play(i)
                if locked { bigFlockSheet = .bird; return }
                flock.you.chirp = i
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHint(locked ? "Plays this chirp. It comes with Big Flock" : "Plays this chirp")
        }
    }

    // MARK: - Actions

    private func hop() {
        guard canHop else { return }
        flock.you.name = trimmedName
        if editing { dismiss(); return }
        UserDefaults.standard.set(true, forKey: "onboarded")
        router.onboarded = true
    }
}
