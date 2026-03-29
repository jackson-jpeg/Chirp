import SwiftUI

struct AddFriendView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var friendCode: String = ""
    @State private var friendName: String = ""
    @State private var peerFingerprint: String = ""
    @State private var showCopied = false
    @State private var radarPhase: CGFloat = 0

    private let amber = Constants.Colors.amber
    private let green = Constants.Colors.electricGreen

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        yourCodeSection
                        addFriendSection
                        nearbySection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(String(localized: "addFriend.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) { dismiss() }
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(amber)
                }
            }
            .task {
                peerFingerprint = await PeerIdentity.shared.fingerprint
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
    }

    // MARK: - Your Code Section

    private var yourCodeSection: some View {
        VStack(spacing: 14) {
            Text(String(localized: "addFriend.yourCode.title"))
                .font(.system(.caption2, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(1)

            // Large code card with amber glow
            VStack(spacing: 16) {
                if peerFingerprint.isEmpty {
                    ProgressView()
                        .tint(amber)
                        .frame(height: 44)
                } else {
                    Text(formattedFingerprint(peerFingerprint))
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .tracking(3)
                        .textSelection(.enabled)
                        .padding(.top, 4)
                }

                // Copy + Share buttons
                HStack(spacing: 16) {
                    Button {
                        UIPasteboard.general.string = peerFingerprint
                        withAnimation(.easeInOut(duration: 0.2)) { showCopied = true }
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation { showCopied = false }
                        }
                    } label: {
                        Label(
                            showCopied ? String(localized: "addFriend.yourCode.copied") : String(localized: "addFriend.yourCode.copy"),
                            systemImage: showCopied ? "checkmark.circle.fill" : "doc.on.doc"
                        )
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(showCopied ? green : amber)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(
                                    showCopied
                                        ? green.opacity(0.12)
                                        : amber.opacity(0.12)
                                )
                        )
                        .contentTransition(.symbolEffect(.replace))
                    }
                    .disabled(peerFingerprint.isEmpty)

                    if !peerFingerprint.isEmpty {
                        ShareLink(
                            item: String(localized: "addFriend.yourCode.shareText \(peerFingerprint)")
                        ) {
                            Label(String(localized: "addFriend.yourCode.share"), systemImage: "square.and.arrow.up")
                                .font(.system(.caption, weight: .semibold))
                                .foregroundStyle(amber)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(amber.opacity(0.12))
                                )
                        }
                    }
                }
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(amber.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: amber.opacity(0.12), radius: 24, y: 2)
            )

            Text(String(localized: "addFriend.yourCode.hint"))
                .font(.system(.caption))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Add Friend Section

    private var addFriendSection: some View {
        VStack(spacing: 12) {
            Text(String(localized: "addFriend.add.title"))
                .font(.system(.caption2, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)

            VStack(spacing: 10) {
                TextField(String(localized: "addFriend.add.codePlaceholder"), text: $friendCode)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced, weight: .medium))
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )

                TextField(String(localized: "addFriend.add.namePlaceholder"), text: $friendName)
                    .textFieldStyle(.plain)
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )

                Button {
                    addFriend()
                } label: {
                    Text(String(localized: "addFriend.add.button"))
                        .font(.system(.body, weight: .bold))
                        .foregroundStyle(canAdd ? .black : .white.opacity(0.3))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(canAdd ? amber : Color.white.opacity(0.08))
                        )
                }
                .disabled(!canAdd)
            }
        }
    }

    // MARK: - Nearby Section

    private var nearbySection: some View {
        let nearbyPeers = appState.multipeerTransport.peers.filter { peer in
            !appState.friendsManager.isFriend(peerID: peer.id)
        }

        return VStack(spacing: 12) {
            HStack {
                Text(String(localized: "addFriend.nearby.title"))
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1)

                Spacer()

                // Pulsing radar indicator
                ZStack {
                    Circle()
                        .stroke(green.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                        .scaleEffect(1 + radarPhase * 0.6)
                        .opacity(1 - radarPhase)

                    Circle()
                        .fill(green)
                        .frame(width: 6, height: 6)
                }
                .onAppear {
                    withAnimation(
                        .easeOut(duration: 1.5)
                        .repeatForever(autoreverses: false)
                    ) {
                        radarPhase = 1.0
                    }
                }

                Text(String(localized: "addFriend.nearby.scanning"))
                    .font(.system(.caption2, weight: .medium))
                    .foregroundStyle(green.opacity(0.7))
            }
            .padding(.leading, 4)

            if nearbyPeers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.secondary.opacity(0.5))

                    Text(String(localized: "addFriend.nearby.lookingForPeople"))
                        .font(.system(.caption))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        )
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(nearbyPeers) { peer in
                        HStack(spacing: 14) {
                            // Avatar
                            ZStack {
                                Circle()
                                    .fill(green.opacity(0.12))
                                    .frame(width: 40, height: 40)

                                Text(String(peer.name.prefix(1)).uppercased())
                                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                                    .foregroundStyle(green)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(peer.name)
                                    .font(.system(.body, weight: .medium))
                                    .foregroundStyle(.white)

                                Text(String(localized: "addFriend.nearby.inRange"))
                                    .font(.system(.caption))
                                    .foregroundStyle(green.opacity(0.8))
                            }

                            Spacer()

                            Button {
                                appState.friendsManager.addFriend(
                                    id: peer.id,
                                    name: peer.name
                                )
                            } label: {
                                Text(String(localized: "addFriend.nearby.add"))
                                    .font(.system(.caption, weight: .bold))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule().fill(amber)
                                    )
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)

                        if peer.id != nearbyPeers.last?.id {
                            Divider()
                                .background(Color.white.opacity(0.06))
                                .padding(.leading, 68)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                )
            }
        }
    }

    // MARK: - Helpers

    private var canAdd: Bool {
        let code = friendCode.replacingOccurrences(of: " ", with: "")
        return !code.isEmpty && code != peerFingerprint
    }

    private func addFriend() {
        let code = friendCode.replacingOccurrences(of: " ", with: "")
        let name = friendName.isEmpty ? "Friend" : friendName
        appState.friendsManager.addFriend(id: code, name: name)
        friendCode = ""
        friendName = ""
        dismiss()
    }

    private func formattedFingerprint(_ fp: String) -> String {
        // Format as pairs: "a4 f2 1b 9c 2e 7d a0 11"
        var result = ""
        for (index, char) in fp.enumerated() {
            if index > 0 && index % 2 == 0 {
                result += " "
            }
            result.append(char)
        }
        return result
    }
}
