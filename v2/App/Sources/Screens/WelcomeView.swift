import SwiftUI

/// The first screen (`v2/design/Welcome`): a full-bleed sunrise with two birds
/// on a wire, the pitch, and the two ways in. Both lead to Make your bird.
struct WelcomeView: View {
    @Environment(Router.self) private var router

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    // Full bleed: the scene runs up under the status bar.
                    WelcomeScene()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Talk to your flock, even with no signal.")
                            .font(.pageTitle)
                            .tracking(-0.48)
                            .foregroundStyle(Theme.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text("Hold to talk to friends nearby. Phones pass your voice along, so it works on the mountain, at the festival and out at sea.")
                            .font(.nunito(17, .bold, relativeTo: .body))
                            .lineSpacing(1.5)
                            .foregroundStyle(Theme.inkBody)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)

                    Spacer(minLength: 28)

                    VStack(spacing: 10) {
                        Button("Start a flock") { router.onboardingStep = .makeBird }
                            .buttonStyle(PrimaryButtonStyle())
                        Button("Join one nearby") { router.onboardingStep = .makeBird }
                            .buttonStyle(SecondaryButtonStyle())
                        Text("No account. No phone number.")
                            .font(.nunito(14, .bold, relativeTo: .footnote))
                            .foregroundStyle(Theme.inkSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 6)
                    }
                    .padding(.horizontal, 20)
                    // 40 from the screen's bottom edge, as drawn (clear of the home indicator).
                    .padding(.bottom, max(40, proxy.safeAreaInsets.bottom + 6))
                }
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .ignoresSafeArea()
        .screenBackground()
    }
}
