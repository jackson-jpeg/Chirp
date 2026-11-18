import SwiftUI

/// The first screen (`v2/design/Welcome`): a full-bleed sunrise with two birds
/// on a wire, the pitch, and the two ways in: name a new birdhouse, or paste a
/// friend's invite. Both then lead to Make your bird.
struct WelcomeView: View {
    @Environment(Router.self) private var router
    @Environment(Mesh.self) private var mesh
    @Environment(Birdhouse.self) private var birdhouse

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    // Full bleed: the scene runs up under the status bar.
                    WelcomeScene()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Talk to your friends, even with no signal.")
                            .font(.pageTitle)
                            .lineHeight(.multiple(factor: 1.1))   // the design's line-height
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
                        Button("Start a birdhouse") { router.onboardingStep = .nameBirdhouse }
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("welcome.start")
                        // The design said "Join one nearby"; you join with a friend's
                        // invite link, so the button says what it does.
                        Button("Join a birdhouse") { router.onboardingStep = .joinBirdhouse }
                            .buttonStyle(SecondaryButtonStyle())
                            .accessibilityIdentifier("welcome.join")
                        Text("No account. No phone number.")
                            .font(.nunito(14, .bold, relativeTo: .footnote))
                            .foregroundStyle(Theme.inkSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 6)
                        // Demo Mode (App Review 2.1(a)): pretend friends, the radio sandboxed.
                        Button { router.enterDemo(mesh, birdhouse: birdhouse) } label: {
                            Text("Try it with pretend friends")
                                .font(.nunito(14, .bold, relativeTo: .footnote))
                                .underline()
                                .foregroundStyle(Theme.inkSecondary)
                                .multilineTextAlignment(.center)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("welcome.demo")
                        .accessibilityHint("Shows the app with pretend friends. Nothing leaves this phone.")
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
