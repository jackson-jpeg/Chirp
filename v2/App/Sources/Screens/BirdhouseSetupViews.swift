import SwiftUI
import UIKit
import ChirpCore

/// Start a birdhouse: name it, then make your bird. No design file covers this
/// screen (Jackson approved the flow, Inbox chirp-2-0-birdhouse-join), so it is
/// built from Make your bird's parts: the eyebrow, the page title, one card
/// with a field, and the primary button at the bottom.
struct NameBirdhouseView: View {
    @Environment(Router.self) private var router
    @Environment(Mesh.self) private var mesh
    @Environment(Birdhouse.self) private var birdhouse
    let back: () -> Void

    init(back: @escaping () -> Void) { self.back = back }

    @State private var name = ""
    @FocusState private var focused: Bool

    private var clean: String { BirdhouseInvite.cleanName(name) }

    var body: some View {
        BirdhouseSetupPage(eyebrow: "Start a birdhouse", title: "Name your birdhouse", back: back) {
            VStack(alignment: .leading, spacing: 6) {
                SetupField(label: "Birdhouse name", prompt: "Ski trip", text: $name, focused: $focused)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .onSubmit(next)
                    .accessibilityIdentifier("birdhouse.name")
                Text("Everyone you invite sees this name.")
                    .font(.nunito(14, .bold, relativeTo: .footnote))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } bottom: {
            Button("Next", action: next)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(clean.isEmpty)
                .opacity(clean.isEmpty ? 0.4 : 1)
                .accessibilityIdentifier("birdhouse.next")
        }
        .onAppear { focused = true }
        .onChange(of: name) { _, new in
            if new.count > BirdhouseInvite.maxNameLength { name = String(new.prefix(BirdhouseInvite.maxNameLength)) }
        }
    }

    private func next() {
        guard !clean.isEmpty else { return }
        router.startBirdhouse(named: clean, mesh: mesh, birdhouse: birdhouse)
    }
}

/// Join a birdhouse: the invite link usually opens the app by itself. This is
/// the fallback when it did not: paste the link (or the code) here.
struct JoinBirdhouseView: View {
    @Environment(Router.self) private var router
    @Environment(Mesh.self) private var mesh
    @Environment(Birdhouse.self) private var birdhouse
    let back: () -> Void

    init(back: @escaping () -> Void) { self.back = back }

    @State private var text = ""
    @State private var refused = false
    @FocusState private var focused: Bool

    var body: some View {
        BirdhouseSetupPage(eyebrow: "Join a birdhouse", title: "Paste your invite", back: back) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Open the invite link a friend sent you and it brings you here. If it doesn't, copy the link and paste it below.")
                    .font(.nunito(15, .bold, relativeTo: .subheadline))
                    .foregroundStyle(Theme.inkBody)
                    .fixedSize(horizontal: false, vertical: true)
                SetupField(label: "Invite link", prompt: "chirpchirps.com/join/...", text: $text, focused: $focused)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .submitLabel(.join)
                    .onSubmit(join)
                    .accessibilityIdentifier("birdhouse.invite")
                // The system paste button reads the clipboard only when tapped,
                // so there is no "allow paste" prompt.
                PasteButton(payloadType: String.self) { strings in
                    guard let s = strings.first else { return }
                    text = s
                    join()
                }
                .buttonBorderShape(.capsule)
                .tint(Theme.ink)
                if refused {
                    Text("That is not a ChirpChirps invite. Ask your friend to send the link again.")
                        .font(.nunito(14, .bold, relativeTo: .footnote))
                        .foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("birdhouse.refused")
                }
            }
        } bottom: {
            Button("Join", action: join)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                .accessibilityIdentifier("birdhouse.join")
        }
        .onChange(of: text) { _, _ in refused = false }
    }

    private func join() {
        guard let channel = BirdhouseInvite.parse(text) else {
            refused = true
            UIAccessibility.post(notification: .announcement, argument: "That is not a ChirpChirps invite.")
            return
        }
        router.join(channel, mesh: mesh, birdhouse: birdhouse)
    }
}

// MARK: - Shared parts

private struct BirdhouseSetupPage<Content: View, Bottom: View>: View {
    let eyebrow: String
    let title: String
    let back: () -> Void
    @ViewBuilder let content: Content
    @ViewBuilder let bottom: Bottom

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: back) {
                    Label("Back", systemImage: "chevron.left")
                        .font(.nunito(15, .black, relativeTo: .subheadline))
                        .foregroundStyle(Theme.ink)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: eyebrow)
                    Text(title)
                        .font(.pageTitle)
                        .tracking(-0.32)
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)

                Card(padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) { content }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
            }
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottom
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .background(Theme.morning.ignoresSafeArea())
        }
        .screenBackground()
    }
}

private struct SetupField: View {
    let label: String
    let prompt: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.nunito(14, .black, relativeTo: .subheadline))
                .foregroundStyle(Theme.inkSecondary)
                .accessibilityHidden(true)
            TextField(label, text: $text, prompt: Text(prompt).foregroundStyle(Theme.inkSecondary))
                .font(.bodyHeavy)
                .foregroundStyle(Theme.ink)
                .autocorrectionDisabled()
                .focused(focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 46)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(focused.wrappedValue ? Theme.solid : Theme.hairline, lineWidth: 2))
        }
        // A tap anywhere on the label or the box's padding focuses the field
        // (the TextField alone answers only on its text line; run 13's UI
        // tests tapped the middle of the block and typed into nothing).
        .contentShape(Rectangle())
        .onTapGesture { focused.wrappedValue = true }
    }
}
