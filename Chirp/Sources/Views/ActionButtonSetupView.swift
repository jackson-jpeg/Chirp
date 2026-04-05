import SwiftUI

/// Guides the user through setting up their Action Button for PTT.
struct ActionButtonSetupView: View {
    @Environment(\.dismiss) private var dismiss

    private let amber = Constants.Colors.amber

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Hero
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(amber.opacity(0.1))
                                .frame(width: 100, height: 100)

                            Image(systemName: "button.horizontal.top.press.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(amber)
                        }

                        Text("Set Up Action Button")
                            .font(.system(.title2, weight: .bold))
                            .foregroundStyle(.white)

                        Text("Use your Action Button as a\nphysical push-to-talk trigger")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)

                    // Steps
                    VStack(spacing: 20) {
                        setupStep(
                            number: 1,
                            icon: "gearshape.fill",
                            title: "Open Settings",
                            detail: "Go to Settings → Action Button on your iPhone"
                        )

                        setupStep(
                            number: 2,
                            icon: "square.grid.2x2.fill",
                            title: "Choose Shortcut",
                            detail: "Select \"Shortcut\" from the Action Button options"
                        )

                        setupStep(
                            number: 3,
                            icon: "magnifyingglass",
                            title: "Find ChirpChirps",
                            detail: "Search for \"Push to Talk\" or \"ChirpChirps\""
                        )

                        setupStep(
                            number: 4,
                            icon: "checkmark.circle.fill",
                            title: "Select \"Push to Talk\"",
                            detail: "Tap it to assign. Now press your Action Button to instantly open ChirpChirps!"
                        )
                    }
                    .padding(.horizontal, 20)

                    // Open Settings button
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.forward.app.fill")
                            Text("Open Settings")
                        }
                        .font(.system(.headline, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(amber)
                        )
                    }
                    .padding(.horizontal, 20)

                    // Tip
                    HStack(spacing: 10) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(amber)
                        Text("Tip: You can also say \"Hey Siri, push to talk with ChirpChirps\" to start a session hands-free.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.05))
                    )
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 40)
            }
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(amber)
                }
            }
        }
    }

    private func setupStep(number: Int, icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(amber.opacity(0.15))
                    .frame(width: 40, height: 40)

                Text("\(number)")
                    .font(.system(.body, weight: .bold))
                    .foregroundStyle(amber)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundStyle(amber)
                    Text(title)
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Text(detail)
                    .font(.system(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}
