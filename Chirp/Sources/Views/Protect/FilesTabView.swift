import SwiftUI

struct FilesTabView: View {
    @Environment(AppState.self) private var appState

    private var activeTransfers: [UUID: TransferProgress] {
        appState.fileTransferService.activeTransfers
    }

    private var inProgressTransfers: [(UUID, TransferProgress)] {
        activeTransfers
            .filter { !$0.value.isComplete }
            .sorted { $0.key.uuidString < $1.key.uuidString }
    }

    private var completedTransfers: [(UUID, TransferProgress)] {
        activeTransfers
            .filter { $0.value.isComplete }
            .sorted { $0.key.uuidString < $1.key.uuidString }
    }

    var body: some View {
        ScrollView {
            if activeTransfers.isEmpty {
                emptyState
            } else {
                VStack(spacing: Constants.Layout.spacing) {
                    if !inProgressTransfers.isEmpty {
                        sectionHeader("Active Transfers")

                        ForEach(inProgressTransfers, id: \.0) { id, transfer in
                            transferCard(id: id, transfer: transfer)
                        }
                    }

                    if !completedTransfers.isEmpty {
                        sectionHeader("Completed")

                        ForEach(completedTransfers, id: \.0) { id, transfer in
                            transferCard(id: id, transfer: transfer)
                        }
                    }
                }
                .padding(.horizontal, Constants.Layout.horizontalPadding)
                .padding(.top, Constants.Layout.horizontalPadding)
                .padding(.bottom, Constants.Layout.horizontalPadding)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Constants.Layout.spacing) {
            Spacer()
                .frame(height: 80)

            Image(systemName: "doc.on.doc")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Constants.Colors.textTertiary)

            Text("No File Transfers")
                .font(Constants.Typography.sectionTitle)
                .foregroundStyle(Constants.Colors.textPrimary)

            Text("Send files through the mesh")
                .font(Constants.Typography.body)
                .foregroundStyle(Constants.Colors.textSecondary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Constants.Colors.textSecondary)
            Spacer()
        }
    }

    // MARK: - Transfer Card

    private func transferCard(id: UUID, transfer: TransferProgress) -> some View {
        let progress: Double = transfer.totalChunks > 0
            ? Double(transfer.receivedChunks) / Double(transfer.totalChunks)
            : 0

        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Constants.Colors.amber.opacity(0.12))
                    .frame(width: 50, height: 50)

                Image(systemName: transfer.isComplete ? "checkmark.circle.fill" : (transfer.isOutbound ? "arrow.up.doc.fill" : "arrow.down.doc.fill"))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(transfer.isComplete ? Constants.Colors.electricGreen : Constants.Colors.amber)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(transfer.fileName)
                    .font(Constants.Typography.cardTitle)
                    .foregroundStyle(Constants.Colors.textPrimary)
                    .lineLimit(1)

                if transfer.isComplete {
                    Text("Complete")
                        .font(Constants.Typography.caption)
                        .foregroundStyle(Constants.Colors.electricGreen)
                } else {
                    HStack(spacing: Constants.Layout.smallSpacing) {
                        ProgressView(value: progress)
                            .tint(Constants.Colors.amber)

                        Text("\(Int(progress * 100))%")
                            .font(Constants.Typography.monoSmall)
                            .foregroundStyle(Constants.Colors.textSecondary)
                    }
                }
            }

            Spacer()

            if transfer.isOutbound {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Constants.Colors.textTertiary)
            } else {
                Image(systemName: "arrow.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Constants.Colors.textTertiary)
            }
        }
        .padding(Constants.Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                .fill(Constants.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                        .fill(.ultraThinMaterial.opacity(0.3))
                        .environment(\.colorScheme, .dark)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                .stroke(Constants.Colors.surfaceBorder, lineWidth: 0.5)
        )
    }
}
