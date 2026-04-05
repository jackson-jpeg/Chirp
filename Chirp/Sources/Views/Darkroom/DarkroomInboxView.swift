import SwiftUI

/// Lists received view-once photos awaiting viewing.
struct DarkroomInboxView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let envelopes = Array(appState.darkroomService.receivedEnvelopes.values)
            .filter { !$0.isExpired }
            .sorted { $0.timestamp > $1.timestamp }

        Group {
            if envelopes.isEmpty {
                emptyState
            } else {
                List(envelopes) { envelope in
                    NavigationLink {
                        DarkroomViewerView(envelopeID: envelope.id)
                    } label: {
                        envelopeRow(envelope)
                    }
                    .listRowBackground(Constants.Colors.slate800.opacity(0.6))
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Constants.Colors.slate900)
        .navigationTitle("Darkroom")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "eye.slash.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Constants.Colors.slate500)

            VStack(spacing: 6) {
                Text("No Photos")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)

                Text("View-once photos sent to you will appear here.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Constants.Colors.slate400)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Row

    private func envelopeRow(_ envelope: DarkroomEnvelope) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Constants.Colors.slate700.opacity(0.6))
                    .frame(width: 44, height: 44)

                Image(systemName: "photo.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Constants.Colors.slate400)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(envelope.senderName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)

                Text(envelope.timestamp.relativeInboxDisplay)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Constants.Colors.slate400)
            }

            Spacer()

            Image(systemName: "eye.circle.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Constants.Colors.amber)
        }
        .padding(.vertical, 4)
    }
}

private extension Date {
    var relativeInboxDisplay: String {
        let interval = Date().timeIntervalSince(self)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}
