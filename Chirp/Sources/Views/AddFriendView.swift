import SwiftUI

struct AddFriendView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var friendCode: String = ""
    @State private var friendName: String = ""
    @State private var peerFingerprint: String = ""
    @State private var showCopied = false

    private let amber = Color(hex: 0xFFB800)
    private let green = Color(hex: 0x30D158)

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        yourCodeSection
                        addFriendSection
                        nearbyPeopleSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Add Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(amber)
                }
            }
            .task {
                peerFingerprint = await PeerIdentity.shared.fingerprint
            }
        }
    }

    // MARK: - Your Code Section

    private var yourCodeSection: some View {
        VStack(spacing: 12) {
            Text("Your Chirp Code")
                .font(.system(.caption, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            VStack(spacing: 10) {
                if peerFingerprint.isEmpty {
                    ProgressView()
                        .tint(amber)
                        .frame(height: 36)
                } else {
                    Text(formattedFingerprint(peerFingerprint))
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .tracking(2)
                        .textSelection(.enabled)
                }

                Button {
                    UIPasteboard.general.string = peerFingerprint
                    withAnimation { showCopied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { showCopied = false }
                    }
                } label: {
                    Label(
                        showCopied ? "Copied!" : "Copy Code",
                        systemImage: showCopied ? "checkmark" : "doc.on.doc"
                    )
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(showCopied ? green : amber)
                }
                .disabled(peerFingerprint.isEmpty)
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(amber.opacity(0.2), lineWidth: 0.5)
                    )
            )

            Text("Share this code with friends so they can add you.")
                .font(.system(.caption))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Add Friend Section

    private var addFriendSection: some View {
        VStack(spacing: 12) {
            Text("Add a Friend")
                .font(.system(.caption, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                TextField("Friend's name", text: $friendName)
                    .textFieldStyle(.plain)
                    .font(.system(.body))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.06))
                    )

                TextField("Paste their Chirp code", text: $friendCode)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.06))
                    )

                Button {
                    let code = friendCode.replacingOccurrences(of: " ", with: "")
                    let name = friendName.isEmpty ? "Friend" : friendName
                    appState.friendsManager.addFriend(id: code, name: name)
                    friendCode = ""
                    friendName = ""
                    dismiss()
                } label: {
                    Text("Add")
                        .font(.system(.body, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(canAdd ? amber : amber.opacity(0.3))
                        )
                }
                .disabled(!canAdd)
            }
        }
    }

    // MARK: - Nearby People Section

    private var nearbyPeopleSection: some View {
        let nearbyPeers = appState.multipeerTransport.peers.filter { peer in
            !appState.friendsManager.isFriend(peerID: peer.id)
        }

        return Group {
            if !nearbyPeers.isEmpty {
                VStack(spacing: 12) {
                    Text("People Nearby")
                        .font(.system(.caption, weight: .bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 0) {
                        ForEach(nearbyPeers) { peer in
                            Button {
                                appState.friendsManager.addFriend(id: peer.id, name: peer.name)
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(green.opacity(0.15))
                                            .frame(width: 38, height: 38)

                                        Text(String(peer.name.prefix(1)).uppercased())
                                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                                            .foregroundStyle(green)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(peer.name)
                                            .font(.system(.body, weight: .medium))
                                            .foregroundStyle(.white)

                                        Text("In range")
                                            .font(.system(.caption))
                                            .foregroundStyle(green)
                                    }

                                    Spacer()

                                    Image(systemName: "person.badge.plus")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(amber)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                            }

                            if peer.id != nearbyPeers.last?.id {
                                Divider()
                                    .background(Color.white.opacity(0.06))
                                    .padding(.leading, 64)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.ultraThinMaterial)
                            .environment(\.colorScheme, .dark)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                            )
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private var canAdd: Bool {
        let code = friendCode.replacingOccurrences(of: " ", with: "")
        return !code.isEmpty && code != peerFingerprint
    }

    private func formattedFingerprint(_ fp: String) -> String {
        // Format as groups of 4 for readability: "abcd efgh ijkl mnop"
        var result = ""
        for (index, char) in fp.enumerated() {
            if index > 0 && index % 4 == 0 {
                result += " "
            }
            result.append(char)
        }
        return result
    }
}
