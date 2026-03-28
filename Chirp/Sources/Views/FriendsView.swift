import SwiftUI

struct FriendsView: View {
    @Environment(AppState.self) private var appState
    @State private var showAddFriend = false
    @State private var selectedFriend: ChirpFriend?

    private let amber = Constants.Colors.amber
    private let green = Constants.Colors.electricGreen

    private var friendCount: Int { appState.friendsManager.friends.count }
    private var onlineFriends: [ChirpFriend] { appState.friendsManager.friends.filter(\.isOnline) }
    private var offlineFriends: [ChirpFriend] { appState.friendsManager.friends.filter { !$0.isOnline } }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            if appState.friendsManager.friends.isEmpty {
                emptyState
            } else {
                friendsList
            }

            // Floating Add Friend button
            if !appState.friendsManager.friends.isEmpty {
                Button {
                    showAddFriend = true
                } label: {
                    Label("Add Friend", systemImage: "person.badge.plus")
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(amber)
                                .shadow(color: amber.opacity(0.4), radius: 12, y: 4)
                        )
                }
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Friends (\(friendCount))")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showAddFriend) {
            AddFriendView()
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            selectedFriend?.name ?? "Friend",
            isPresented: Binding(
                get: { selectedFriend != nil },
                set: { if !$0 { selectedFriend = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let friend = selectedFriend {
                Button("Start Channel") {
                    startDirectChannel(with: friend)
                }
                Button("Remove", role: .destructive) {
                    withAnimation {
                        appState.friendsManager.removeFriend(id: friend.id)
                    }
                }
                Button("Cancel", role: .cancel) {
                    selectedFriend = nil
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            // Illustration-style view
            ZStack {
                Circle()
                    .fill(amber.opacity(0.06))
                    .frame(width: 140, height: 140)

                Circle()
                    .fill(amber.opacity(0.04))
                    .frame(width: 180, height: 180)

                VStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(amber.opacity(0.5))

                    Image(systemName: "wave.3.right")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(amber.opacity(0.3))
                }
            }

            VStack(spacing: 10) {
                Text("Add friends to start talking")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)

                Text("Share your ChirpChirp code or\ndiscover people nearby.")
                    .font(.system(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Button {
                showAddFriend = true
            } label: {
                Label("Add Friend", systemImage: "person.badge.plus")
                    .font(.system(.body, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(amber)
                            .shadow(color: amber.opacity(0.3), radius: 12, y: 4)
                    )
            }
            .padding(.top, 4)

            Spacer()
        }
    }

    // MARK: - Friends List

    private var friendsList: some View {
        ScrollView {
            VStack(spacing: 28) {
                // In Range section
                if !onlineFriends.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("In Range", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.system(.caption, weight: .bold))
                            .foregroundStyle(green)
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .padding(.leading, 4)

                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 12
                        ) {
                            ForEach(onlineFriends) { friend in
                                onlineFriendCard(friend)
                            }
                        }
                    }
                }

                // All Friends section (offline)
                if !offlineFriends.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("All Friends")
                            .font(.system(.caption, weight: .bold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .padding(.leading, 4)

                        VStack(spacing: 0) {
                            ForEach(offlineFriends) { friend in
                                offlineFriendRow(friend)

                                if friend.id != offlineFriends.last?.id {
                                    Divider()
                                        .background(Color.white.opacity(0.06))
                                        .padding(.leading, 60)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.04))
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 100) // Space for floating button
        }
    }

    // MARK: - Online Friend Card

    private func onlineFriendCard(_ friend: ChirpFriend) -> some View {
        Button {
            selectedFriend = friend
        } label: {
            VStack(spacing: 12) {
                // Avatar with green glow
                ZStack {
                    Circle()
                        .fill(avatarGradient(for: friend.id))
                        .frame(width: 52, height: 52)
                        .shadow(color: green.opacity(0.4), radius: 10)

                    Text(String(friend.name.prefix(1)).uppercased())
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 4) {
                    Text(friend.name)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    // Signal indicator
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(green)
                                .frame(width: 4, height: CGFloat(6 + i * 3))
                        }
                    }
                    .frame(height: 12)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(green.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: green.opacity(0.15), radius: 16)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Offline Friend Row

    private func offlineFriendRow(_ friend: ChirpFriend) -> some View {
        HStack(spacing: 14) {
            // Avatar — gray toned
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 42, height: 42)

                Text(String(friend.name.prefix(1)).uppercased())
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(.gray)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(friend.name)
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))

                if let lastSeen = friend.lastSeen {
                    Text(lastSeen, format: .relative(presentation: .named))
                        .font(.system(.caption))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Never seen")
                        .font(.system(.caption))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private func startDirectChannel(with friend: ChirpFriend) {
        let channel = appState.channelManager.createChannel(
            name: friend.name,
            accessMode: .locked,
            ownerID: appState.localPeerID
        )
        appState.channelManager.joinChannel(id: channel.id)
    }

    private func avatarGradient(for id: String) -> LinearGradient {
        let gradients: [(Color, Color)] = [
            (Color(hex: 0xFFB800), Color(hex: 0xFF8C00)),
            (Color(hex: 0x30D158), Color(hex: 0x00C7BE)),
            (Color(hex: 0x5E5CE6), Color(hex: 0xBF5AF2)),
            (Color(hex: 0xFF6B6B), Color(hex: 0xFF2D55)),
            (Color(hex: 0x64D2FF), Color(hex: 0x5E5CE6)),
            (Color(hex: 0xBF5AF2), Color(hex: 0xFF2D55)),
        ]
        let hash = id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let pair = gradients[abs(hash) % gradients.count]
        return LinearGradient(
            colors: [pair.0, pair.1],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
