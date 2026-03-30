import SwiftUI

struct CICADARevealView: View {
    let hiddenText: String
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Constants.Colors.amber)
                Text("Hidden Message")
                    .font(Constants.Typography.sectionTitle)
                    .foregroundStyle(Constants.Colors.textPrimary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Constants.Colors.textTertiary)
                }
            }

            // Divider
            Rectangle()
                .fill(Constants.Colors.surfaceBorder)
                .frame(height: 1)

            // Hidden content
            Text(hiddenText)
                .font(.system(.body, weight: .medium))
                .foregroundStyle(Constants.Colors.amber)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Constants.Colors.amber.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            // Security note
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                Text("Encrypted with channel key")
                    .font(Constants.Typography.monoSmall)
            }
            .foregroundStyle(Constants.Colors.textTertiary)
        }
        .padding(Constants.Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                .fill(Constants.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                        .stroke(Constants.Colors.amber.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: Constants.Colors.amber.opacity(0.15), radius: 20, y: 8)
        .padding(.horizontal, Constants.Layout.horizontalPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hidden message: \(hiddenText)")
    }
}
