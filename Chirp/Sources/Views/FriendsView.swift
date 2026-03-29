import SwiftUI

struct FriendsView: View {
    @Environment(AppState.self) private var appState
    @State private var showAddFriend = false
    @State private var selectedFriend: ChirpFriend?
    @State private var detailFriend: ChirpFriend?
    @State private var breathePhase: CGFloat = 0
    @State private var isRefreshing = false

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
                    Label(String(localized: "friends.addFriend"), systemImage: "person.badge.plus")
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
        .toolbar {
            ToolbarItem(placement: .principal) {
                EmptyView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) {
            customHeader
        }
        .sheet(isPresented: $showAddFriend) {
            AddFriendView()
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $detailFriend) { friend in
            FriendDetailSheet(
                friend: friend,
                avatarGradient: avatarGradient(for: friend.id),
                onTalk: { startDirectChannel(with: friend) },
                onRemove: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        appState.friendsManager.removeFriend(id: friend.id)
                    }
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationBackground(.ultraThinMaterial)
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
                Button(String(localized: "friends.action.startChannel")) {
                    startDirectChannel(with: friend)
                }
                Button(String(localized: "friends.action.viewDetails")) {
                    detailFriend = friend
                }
                Button(String(localized: "friends.action.remove"), role: .destructive) {
                    withAnimation {
                        appState.friendsManager.removeFriend(id: friend.id)
                    }
                }
                Button(String(localized: "common.cancel"), role: .cancel) {
                    selectedFriend = nil
                }
            }
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: true)
            ) {
                breathePhase = 1
            }
        }
    }

    // MARK: - Custom Header

    private var customHeader: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text(String(localized: "friends.title"))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                HStack(spacing: 8) {
                    // Total friends pill
                    pillBadge(
                        icon: "person.2.fill",
                        text: "\(friendCount)",
                        color: amber
                    )

                    // Online count pill
                    if !onlineFriends.isEmpty {
                        pillBadge(
                            icon: "antenna.radiowaves.left.and.right",
                            text: "\(onlineFriends.count)",
                            color: green
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 14)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .top)
            )
        }
    }

    private func pillBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 13, weight: .bold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
                .overlay(
                    Capsule()
                        .stroke(color.opacity(0.2), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 28) {
            Spacer()

            PerchBirdsView(size: 220, isAnimating: true)
                .padding(.bottom, 4)

            VStack(spacing: 12) {
                Text(String(localized: "friends.emptyState.title"))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)

                Text(String(localized: "friends.emptyState.subtitle"))
                    .font(.system(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            // Share Code hint
            HStack(spacing: 10) {
                Image(systemName: "qrcode")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(amber.opacity(0.6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "friends.emptyState.shareCodeTitle"))
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(String(localized: "friends.emptyState.shareCodeSubtitle"))
                        .font(.system(.caption2))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(amber.opacity(0.1), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 32)

            Button {
                showAddFriend = true
            } label: {
                Label(String(localized: "friends.addFriend"), systemImage: "person.badge.plus")
                    .font(.system(.body, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 15)
                    .background(
                        Capsule()
                            .fill(amber)
                            .shadow(color: amber.opacity(0.35), radius: 16, y: 6)
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
                        HStack(spacing: 8) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(green)

                            Text(String(localized: "friends.section.inRange"))
                                .font(.system(.caption, weight: .bold))
                                .foregroundStyle(green)
                                .tracking(0.5)

                            // Pulsing dot
                            Circle()
                                .fill(green)
                                .frame(width: 6, height: 6)
                                .scaleEffect(1.0 + breathePhase * 0.4)
                                .opacity(Double(1.0 - breathePhase * 0.3))
                        }
                        .padding(.leading, 4)

                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 12
                        ) {
                            ForEach(onlineFriends) { friend in
                                onlineFriendCard(friend)
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                                        removal: .scale(scale: 0.8).combined(with: .opacity)
                                    ))
                            }
                        }
                    }
                    .animation(.easeInOut(duration: 0.4), value: onlineFriends.map(\.id))
                }

                // Offline Friends section
                if !offlineFriends.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(String(localized: "friends.section.offline"))
                            .font(.system(.caption, weight: .bold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .padding(.leading, 4)

                        VStack(spacing: 0) {
                            ForEach(offlineFriends) { friend in
                                offlineFriendRow(friend)
                                    .transition(.opacity.combined(with: .move(edge: .leading)))

                                if friend.id != offlineFriends.last?.id {
                                    Divider()
                                        .background(Color.white.opacity(0.06))
                                        .padding(.leading, 64)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(.ultraThinMaterial.opacity(0.4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                                )
                        )
                    }
                    .animation(.easeInOut(duration: 0.35), value: offlineFriends.map(\.id))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
        .refreshable {
            // Pull-to-refresh triggers a scan cycle
            isRefreshing = true
            try? await Task.sleep(for: .seconds(1))
            isRefreshing = false
        }
    }

    // MARK: - Online Friend Card

    private func onlineFriendCard(_ friend: ChirpFriend) -> some View {
        Button {
            detailFriend = friend
        } label: {
            VStack(spacing: 12) {
                // Avatar with breathing green glow
                ZStack {
                    // Animated breathing glow layers
                    Circle()
                        .fill(green.opacity(0.08))
                        .frame(width: 68, height: 68)
                        .scaleEffect(1.0 + breathePhase * 0.15)

                    Circle()
                        .fill(green.opacity(0.05))
                        .frame(width: 78, height: 78)
                        .scaleEffect(1.0 + breathePhase * 0.1)

                    Circle()
                        .fill(avatarGradient(for: friend.id))
                        .frame(width: 54, height: 54)
                        .shadow(color: green.opacity(0.3 + breathePhase * 0.2), radius: 12 + breathePhase * 4)

                    Text(String(friend.name.prefix(1)).uppercased())
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    // Online indicator dot
                    Circle()
                        .fill(green)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(Color.black, lineWidth: 2)
                        )
                        .offset(x: 20, y: 18)
                }

                VStack(spacing: 6) {
                    Text(friend.name)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    // Signal strength bars
                    signalBars(strength: signalStrength(for: friend))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(green.opacity(0.15 + breathePhase * 0.1), lineWidth: 1)
                    )
                    .shadow(color: green.opacity(0.1 + breathePhase * 0.05), radius: 20)
            )
        }
        .buttonStyle(CardPressStyle())
        .contextMenu {
            Button {
                startDirectChannel(with: friend)
            } label: {
                Label(String(localized: "friends.action.startChannel"), systemImage: "waveform")
            }
            Button(role: .destructive) {
                withAnimation {
                    appState.friendsManager.removeFriend(id: friend.id)
                }
            } label: {
                Label(String(localized: "friends.action.removeFriend"), systemImage: "person.badge.minus")
            }
        }
    }

    // MARK: - Signal Bars

    private func signalBars(strength: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < strength ? green : Color.white.opacity(0.15))
                    .frame(width: 4, height: CGFloat(5 + i * 3))
            }
        }
        .frame(height: 14)
    }

    private func signalStrength(for friend: ChirpFriend) -> Int {
        // Derive signal strength from peer ID hash for visual variety
        // In a real implementation this would come from RSSI or latency
        let hash = friend.id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return 2 + (abs(hash) % 3) // 2-4 bars for online friends
    }

    // MARK: - Offline Friend Row

    private func offlineFriendRow(_ friend: ChirpFriend) -> some View {
        Button {
            detailFriend = friend
        } label: {
            HStack(spacing: 14) {
                // Avatar - gray, subtle opacity
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 44, height: 44)

                    Text(String(friend.name.prefix(1)).uppercased())
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .foregroundStyle(.gray.opacity(0.5))
                }
                .opacity(0.7)

                VStack(alignment: .leading, spacing: 3) {
                    Text(friend.name)
                        .font(.system(.body, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))

                    if let lastSeen = friend.lastSeen {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 5, height: 5)
                            Text(lastSeen, format: .relative(presentation: .named))
                                .font(.system(.caption))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 5, height: 5)
                            Text(String(localized: "friends.status.neverSeen"))
                                .font(.system(.caption))
                                .foregroundStyle(.secondary.opacity(0.7))
                        }
                    }
                }

                Spacer()

                // Chevron hint
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.15))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                startDirectChannel(with: friend)
            } label: {
                Label(String(localized: "friends.action.startChannel"), systemImage: "waveform")
            }
            Button(role: .destructive) {
                withAnimation {
                    appState.friendsManager.removeFriend(id: friend.id)
                }
            } label: {
                Label(String(localized: "friends.action.removeFriend"), systemImage: "person.badge.minus")
            }
        }
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

// MARK: - Friend Detail Sheet

private struct FriendDetailSheet: View {
    let friend: ChirpFriend
    let avatarGradient: LinearGradient
    let onTalk: () -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showRemoveConfirm = false
    @State private var breathe: CGFloat = 0

    private let amber = Constants.Colors.amber
    private let green = Constants.Colors.electricGreen

    var body: some View {
        ZStack {
            Color.clear

            VStack(spacing: 24) {
                // Handle bar spacer
                Spacer().frame(height: 8)

                // Large avatar with status
                ZStack {
                    if friend.isOnline {
                        Circle()
                            .fill(green.opacity(0.06))
                            .frame(width: 120, height: 120)
                            .scaleEffect(1 + breathe * 0.1)

                        Circle()
                            .fill(green.opacity(0.04))
                            .frame(width: 140, height: 140)
                            .scaleEffect(1 + breathe * 0.08)
                    }

                    Circle()
                        .fill(avatarGradient)
                        .frame(width: 88, height: 88)
                        .shadow(
                            color: friend.isOnline ? green.opacity(0.3) : .clear,
                            radius: 16
                        )

                    Text(String(friend.name.prefix(1)).uppercased())
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    // Status badge
                    Circle()
                        .fill(friend.isOnline ? green : Color.gray.opacity(0.4))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle()
                                .stroke(Color(uiColor: .systemBackground), lineWidth: 3)
                        )
                        .offset(x: 32, y: 32)
                }

                // Name and info
                VStack(spacing: 6) {
                    Text(friend.name)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(formattedPeerID(friend.id))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                    // Status / last seen
                    if friend.isOnline {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(green)
                                .frame(width: 6, height: 6)
                            Text(String(localized: "friends.status.inRange"))
                                .font(.system(.caption, weight: .semibold))
                                .foregroundStyle(green)
                        }
                        .padding(.top, 2)
                    } else if let lastSeen = friend.lastSeen {
                        HStack(spacing: 5) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                            Text(String(localized: "friends.status.lastSeen"))
                            + Text(lastSeen, format: .relative(presentation: .named))
                        }
                        .font(.system(.caption))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    }
                }

                // Action buttons
                HStack(spacing: 16) {
                    // Talk button
                    Button {
                        onTalk()
                        dismiss()
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(amber)
                                    .frame(width: 52, height: 52)
                                Image(systemName: "waveform")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.black)
                            }
                            Text(String(localized: "friends.detail.talk"))
                                .font(.system(.caption, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }

                    // Message button
                    Button {
                        // Future: open direct message
                        dismiss()
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(width: 52, height: 52)
                                Image(systemName: "text.bubble")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            Text(String(localized: "friends.detail.message"))
                                .font(.system(.caption, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }

                Spacer()

                // Remove button at bottom
                Button(role: .destructive) {
                    showRemoveConfirm = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.minus")
                            .font(.system(size: 13, weight: .medium))
                        Text(String(localized: "friends.action.removeFriend"))
                            .font(.system(.subheadline, weight: .medium))
                    }
                    .foregroundStyle(Constants.Colors.hotRed.opacity(0.8))
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Constants.Colors.hotRed.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Constants.Colors.hotRed.opacity(0.12), lineWidth: 0.5)
                            )
                    )
                    .padding(.horizontal, 40)
                }
                .confirmationDialog(
                    "Remove \(friend.name)?",
                    isPresented: $showRemoveConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Remove", role: .destructive) {
                        onRemove()
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) {}
                }

                Spacer().frame(height: 16)
            }
        }
        .onAppear {
            guard friend.isOnline else { return }
            withAnimation(
                .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: true)
            ) {
                breathe = 1
            }
        }
    }

    private func formattedPeerID(_ id: String) -> String {
        let short = String(id.prefix(16))
        var result = ""
        for (index, char) in short.enumerated() {
            if index > 0 && index % 4 == 0 { result += " " }
            result.append(char)
        }
        return result + (id.count > 16 ? "..." : "")
    }
}

// MARK: - Card Press Style

private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
