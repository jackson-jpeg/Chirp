import SwiftUI

struct FriendsView: View {
    @Environment(AppState.self) private var appState
    @State private var showAddFriend = false

    private let amber = Color(hex: 0xFFB800)
    private let green = Color(hex: 0x30D158)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if appState.friendsManager.friends.isEmpty {
                emptyState
            } else {
                friendsList
            }
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddFriend = true
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(amber)
                }
            }
        }
        .sheet(isPresented: $showAddFriend) {
            AddFriendView()
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(amber.opacity(0.08))
                    .frame(width: 100, height: 100)

                Image(systemName: "person.2")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(amber.opacity(0.6))
            }

            VStack(spacing: 8) {
                Text("No friends yet")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)

                Text("Share your Chirp code with\nsomeone nearby.")
                    .font(.system(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Button {
                showAddFriend = true
            } label: {
                Label("Add Friend", systemImage: "person.badge.plus")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule().fill(amber)
                    )
            }
            .padding(.top, 8)

            Spacer()
        }
    }

    // MARK: - Friends List

    private var friendsList: some View {
        let online = appState.friendsManager.friends.filter(\.isOnline)
        let offline = appState.friendsManager.friends.filter { !$0.isOnline }

        return List {
            if !online.isEmpty {
                Section {
                    ForEach(online) { friend in
                        friendRow(friend)
                    }
                    .onDelete { offsets in
                        deleteFriends(from: online, at: offsets)
                    }
                } header: {
                    Label("In Range", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.system(.caption, weight: .bold))
                        .foregroundStyle(green)
                }
            }

            if !offline.isEmpty {
                Section {
                    ForEach(offline) { friend in
                        friendRow(friend)
                    }
                    .onDelete { offsets in
                        deleteFriends(from: offline, at: offsets)
                    }
                } header: {
                    Text("Offline")
                        .font(.system(.caption, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Friend Row

    private func friendRow(_ friend: ChirpFriend) -> some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(avatarColor(for: friend.id).opacity(0.2))
                    .frame(width: 44, height: 44)

                Text(String(friend.name.prefix(1)).uppercased())
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(avatarColor(for: friend.id))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(friend.name)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(.white)

                HStack(spacing: 6) {
                    Circle()
                        .fill(friend.isOnline ? green : Color.gray.opacity(0.5))
                        .frame(width: 7, height: 7)

                    if friend.isOnline {
                        Text("In Range")
                            .font(.system(.caption, weight: .medium))
                            .foregroundStyle(green)
                    } else if let lastSeen = friend.lastSeen {
                        Text("Last seen: \(lastSeen, format: .relative(presentation: .named))")
                            .font(.system(.caption))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Never seen")
                            .font(.system(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if friend.isOnline {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(amber)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.clear)
    }

    // MARK: - Helpers

    private func deleteFriends(from list: [ChirpFriend], at offsets: IndexSet) {
        for index in offsets {
            let friend = list[index]
            withAnimation {
                appState.friendsManager.removeFriend(id: friend.id)
            }
        }
    }

    private func avatarColor(for id: String) -> Color {
        let colors: [Color] = [
            amber,
            Color(hex: 0x30D158),
            Color(hex: 0x5E5CE6),
            Color(hex: 0xFF6B6B),
            Color(hex: 0x64D2FF),
            Color(hex: 0xBF5AF2),
        ]
        let hash = id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return colors[abs(hash) % colors.count]
    }
}
