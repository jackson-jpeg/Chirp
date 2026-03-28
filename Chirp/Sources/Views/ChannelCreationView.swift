import SwiftUI

struct ChannelCreationView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var channelName = ""
    @FocusState private var isNameFocused: Bool

    private let suggestedNames = ["Squad", "Family", "Team", "Base Camp", "Road Trip", "Crew"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Channel icon
                ZStack {
                    Circle()
                        .fill(Color(hex: 0xFFB800).opacity(0.15))
                        .frame(width: 72, height: 72)

                    Circle()
                        .stroke(Color(hex: 0xFFB800).opacity(0.3), lineWidth: 1)
                        .frame(width: 72, height: 72)

                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Color(hex: 0xFFB800))
                }
                .padding(.top, 28)
                .padding(.bottom, 16)

                Text("Create a Channel")
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(.white)

                Text("Everyone on the same channel can talk")
                    .font(.system(.subheadline))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                    .padding(.bottom, 28)

                // Name input
                VStack(alignment: .leading, spacing: 8) {
                    Text("CHANNEL NAME")
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)

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
                                                ? Color(hex: 0xFFB800)
                                                : Color.white.opacity(0.1),
                                            lineWidth: isNameFocused ? 1.5 : 1
                                        )
                                )
                        )
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            createChannel()
                        }
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 24)

                // Suggested names
                VStack(alignment: .leading, spacing: 8) {
                    Text("SUGGESTIONS")
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)

                    FlowLayout(spacing: 8) {
                        ForEach(suggestedNames, id: \.self) { name in
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    channelName = name
                                }
                            } label: {
                                Text(name)
                                    .font(.system(.subheadline, weight: .medium))
                                    .foregroundStyle(
                                        channelName == name
                                            ? .black
                                            : Color(hex: 0xFFB800)
                                    )
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(
                                                channelName == name
                                                    ? Color(hex: 0xFFB800)
                                                    : Color(hex: 0xFFB800).opacity(0.12)
                                            )
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(
                                                channelName == name
                                                    ? Color.clear
                                                    : Color(hex: 0xFFB800).opacity(0.3),
                                                lineWidth: 1
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                Spacer()

                // Create button
                Button(action: createChannel) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18, weight: .semibold))

                        Text("Create Channel")
                            .font(.system(.headline, weight: .bold))
                    }
                    .foregroundStyle(isValid ? .black : .white.opacity(0.3))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isValid ? Color(hex: 0xFFB800) : Color.white.opacity(0.08))
                    )
                }
                .disabled(!isValid)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
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
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
    }

    private var isValid: Bool {
        !channelName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func createChannel() {
        let name = channelName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let channel = appState.channelManager.createChannel(name: name)
        appState.channelManager.joinChannel(id: channel.id)
        dismiss()
    }
}

// MARK: - Flow Layout for suggestion chips

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct ArrangeResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }

        return ArrangeResult(
            size: CGSize(width: maxWidth, height: totalHeight),
            positions: positions
        )
    }
}
