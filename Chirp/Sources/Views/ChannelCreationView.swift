import SwiftUI

struct ChannelCreationView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    enum Mode: CaseIterable {
        case create
        case join

        var label: String {
            switch self {
            case .create: return String(localized: "channelCreation.mode.create")
            case .join: return String(localized: "channelCreation.mode.join")
            }
        }
    }

    @State private var mode: Mode = .create
    @State private var channelName = ""
    @State private var inviteCode = ""
    @State private var isPrivate = false
    @State private var joinFailed = false
    @FocusState private var isNameFocused: Bool
    @FocusState private var isCodeFocused: Bool

    private let suggestedNames = ["Squad", "Base Camp", "Family", "Road Trip", "The Crew", "HQ"]
    private let amber = Constants.Colors.amber
    private let green = Constants.Colors.electricGreen

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented picker
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 28)

                if mode == .create {
                    createModeContent
                } else {
                    joinModeContent
                }
            }
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: mode)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
    }

    // MARK: - Create Mode

    private var createModeContent: some View {
        VStack(spacing: 0) {
            // Channel name field — large centered with amber underline
            VStack(spacing: 6) {
                TextField(String(localized: "channelCreation.create.namePlaceholder"), text: $channelName)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .autocorrectionDisabled()
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .onSubmit { createChannel() }
                    .padding(.horizontal, 24)

                // Amber underline
                Rectangle()
                    .fill(amber.opacity(isNameFocused ? 1.0 : 0.4))
                    .frame(height: 2)
                    .frame(maxWidth: 200)
                    .animation(.easeInOut(duration: 0.2), value: isNameFocused)
            }
            .padding(.bottom, 24)

            // Private channel toggle
            HStack(spacing: 12) {
                Image(systemName: isPrivate ? "lock.fill" : "lock.open")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isPrivate ? amber : .secondary)
                    .frame(width: 24)
                    .contentTransition(.symbolEffect(.replace))

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "channelCreation.create.privateChannel"))
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)

                    if isPrivate {
                        Text(String(localized: "channelCreation.create.privateChannelHint"))
                            .font(.system(.caption))
                            .foregroundStyle(.secondary)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                Spacer()

                Toggle("", isOn: $isPrivate)
                    .tint(amber)
                    .labelsHidden()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.05))
            )
            .padding(.horizontal, 24)
            .animation(.easeInOut(duration: 0.2), value: isPrivate)

            // Suggested name chips
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "channelCreation.create.suggestions"))
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                    .padding(.leading, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(suggestedNames, id: \.self) { name in
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    channelName = name
                                }
                            } label: {
                                Text(name)
                                    .font(.system(.subheadline, weight: .semibold))
                                    .foregroundStyle(
                                        channelName == name ? .black : amber
                                    )
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 9)
                                    .background(
                                        Capsule()
                                            .fill(
                                                channelName == name
                                                    ? amber
                                                    : amber.opacity(0.1)
                                            )
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(
                                                channelName == name
                                                    ? Color.clear
                                                    : amber.opacity(0.25),
                                                lineWidth: 1
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Spacer()

            // Create button
            Button(action: createChannel) {
                Text(String(localized: "channelCreation.create.button"))
                    .font(.system(.headline, weight: .bold))
                    .foregroundStyle(isCreateValid ? .black : .white.opacity(0.3))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isCreateValid ? amber : Color.white.opacity(0.08))
                    )
            }
            .disabled(!isCreateValid)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .onAppear { isNameFocused = true }
    }

    // MARK: - Join Mode

    private var joinModeContent: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 20)

            // Code entry
            VStack(spacing: 16) {
                Image(systemName: "ticket")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(amber.opacity(0.7))
                    .padding(.bottom, 4)

                TextField(String(localized: "channelCreation.join.codePlaceholder"), text: $inviteCode)
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .focused($isCodeFocused)
                    .submitLabel(.go)
                    .onSubmit { joinChannel() }
                    .onChange(of: inviteCode) { _, newValue in
                        inviteCode = String(newValue.uppercased().prefix(12))
                    }
                    .padding(.horizontal, 24)

                // Amber underline
                Rectangle()
                    .fill(amber.opacity(isCodeFocused ? 1.0 : 0.4))
                    .frame(height: 2)
                    .frame(maxWidth: 240)

                Text(String(localized: "channelCreation.join.hint"))
                    .font(.system(.caption))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)

                if joinFailed {
                    Label(String(localized: "channelCreation.join.invalidCode"), systemImage: "exclamationmark.triangle")
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(Constants.Colors.hotRed)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Join button
            Button(action: joinChannel) {
                Text(String(localized: "channelCreation.join.button"))
                    .font(.system(.headline, weight: .bold))
                    .foregroundStyle(isJoinValid ? .black : .white.opacity(0.3))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isJoinValid ? amber : Color.white.opacity(0.08))
                    )
            }
            .disabled(!isJoinValid)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .onAppear { isCodeFocused = true }
    }

    // MARK: - Validation

    private var isCreateValid: Bool {
        !channelName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var isJoinValid: Bool {
        !inviteCode.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Actions

    private func createChannel() {
        let name = channelName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let accessMode: ChirpChannel.AccessMode = isPrivate ? .locked : .open
        let ownerID: String? = isPrivate ? appState.localPeerID : nil

        let channel = appState.channelManager.createChannel(
            name: name,
            accessMode: accessMode,
            ownerID: ownerID
        )
        appState.channelManager.joinChannel(id: channel.id)
        dismiss()
    }

    private func joinChannel() {
        let code = inviteCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }

        let success = appState.channelManager.joinWithInviteCode(code)
        if success {
            dismiss()
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                joinFailed = true
            }
            Task {
                try? await Task.sleep(for: .seconds(3))
                withAnimation { joinFailed = false }
            }
        }
    }
}
