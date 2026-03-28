import SwiftUI

struct ChannelCreationView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var channelName = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // Channel icon
                ZStack {
                    Circle()
                        .fill(Color(hex: 0xFFB800).opacity(0.15))
                        .frame(width: 80, height: 80)

                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(Color(hex: 0xFFB800))
                }
                .padding(.top, 32)

                Text("Create a Channel")
                    .font(.system(.title2, weight: .bold))
                    .foregroundStyle(.white)

                // Name input
                VStack(alignment: .leading, spacing: 8) {
                    Text("CHANNEL NAME")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(.secondary)

                    TextField("e.g. Road Trip Crew", text: $channelName)
                        .font(.system(.body, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.07))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            isNameFocused
                                            ? Color(hex: 0xFFB800).opacity(0.5)
                                            : Color.white.opacity(0.1),
                                            lineWidth: 1
                                        )
                                )
                        )
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            createChannel()
                        }
                }
                .padding(.horizontal, 24)

                Spacer()

                // Create button
                Button(action: createChannel) {
                    Text("Create")
                        .font(.system(.headline, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    channelName.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? Color.gray.opacity(0.3)
                                    : Color(hex: 0xFFB800)
                                )
                        )
                }
                .disabled(channelName.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .onAppear {
                isNameFocused = true
            }
        }
    }

    private func createChannel() {
        let name = channelName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        appState.channelManager.createChannel(name: name)
        dismiss()
    }
}
