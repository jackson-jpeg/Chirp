import SwiftUI
import OSLog

/// Live translation view for the Babel feature.
///
/// Displays a real-time translation feed with language pair selection,
/// pipeline status, and PTT-style start/stop controls.
struct BabelView: View {
    @Bindable var babelService: BabelService

    let localPeerID: String
    let localPeerName: String
    let channelID: String

    @State private var sourceLanguage: String = "en-US"
    @State private var targetLanguage: String = "es"
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    private let logger = Logger(subsystem: Constants.subsystem, category: "BabelView")

    // MARK: - Common Languages

    private let languages: [(code: String, name: String)] = [
        ("en-US", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt-BR", "Portuguese"),
        ("zh-Hans", "Chinese"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("ar", "Arabic"),
        ("ru", "Russian"),
        ("hi", "Hindi"),
        ("uk", "Ukrainian"),
        ("pl", "Polish"),
        ("tr", "Turkish"),
    ]

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Constants.Colors.backgroundPrimary,
                    Color(hex: 0x050510),
                    Color(hex: 0x0A0A1A),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                languagePairSelector
                statusIndicator
                translationFeed
                controls
            }
        }
        .alert("Translation Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Live Translate")
                    .font(Constants.Typography.heroTitle)
                    .foregroundStyle(Constants.Colors.textPrimary)

                Text("BABEL")
                    .font(Constants.Typography.mono)
                    .foregroundStyle(Constants.Colors.amber)
            }

            Spacer()

            // Babel status icon
            Image(systemName: "globe")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(
                    babelService.isTranslating
                        ? Constants.Colors.electricGreen
                        : Constants.Colors.textTertiary
                )
                .symbolEffect(.pulse, isActive: babelService.isTranslating)
        }
        .padding(.horizontal, Constants.Layout.horizontalPadding)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Language Pair Selector

    private var languagePairSelector: some View {
        HStack(spacing: 12) {
            // Source language picker
            languagePicker(
                label: "FROM",
                selection: $sourceLanguage
            )

            // Swap button
            Button {
                withAnimation(.spring(response: Constants.Animations.springResponse, dampingFraction: Constants.Animations.springDamping)) {
                    let temp = sourceLanguage
                    sourceLanguage = targetLanguage
                    targetLanguage = temp
                }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Constants.Colors.amber)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(Constants.Colors.glassAmber)
                            .overlay(
                                Circle()
                                    .strokeBorder(Constants.Colors.glassAmberBorder, lineWidth: 1)
                            )
                    )
            }
            .disabled(babelService.isTranslating)

            // Target language picker
            languagePicker(
                label: "TO",
                selection: $targetLanguage
            )
        }
        .padding(.horizontal, Constants.Layout.horizontalPadding)
        .padding(.bottom, Constants.Layout.spacing)
    }

    private func languagePicker(label: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Constants.Typography.badge)
                .foregroundStyle(Constants.Colors.textTertiary)

            Menu {
                ForEach(languages, id: \.code) { lang in
                    Button(lang.name) {
                        selection.wrappedValue = lang.code
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(languageName(for: selection.wrappedValue))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Constants.Colors.textPrimary)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Constants.Colors.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Constants.Layout.buttonCornerRadius)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Layout.buttonCornerRadius)
                        .strokeBorder(Constants.Colors.surfaceBorder, lineWidth: 1)
                )
            }
            .disabled(babelService.isTranslating)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Status Indicator

    private var statusIndicator: some View {
        HStack(spacing: 8) {
            if babelService.isTranslating {
                // Pipeline stage indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(statusText)
                    .font(Constants.Typography.monoStatus)
                    .foregroundStyle(statusColor)

                if !babelService.currentPartialText.isEmpty {
                    Spacer()

                    Text(babelService.currentPartialText)
                        .font(Constants.Typography.caption)
                        .foregroundStyle(Constants.Colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } else {
                Circle()
                    .fill(Constants.Colors.textTertiary)
                    .frame(width: 8, height: 8)

                Text("IDLE")
                    .font(Constants.Typography.monoStatus)
                    .foregroundStyle(Constants.Colors.textTertiary)
            }

            Spacer()
        }
        .padding(.horizontal, Constants.Layout.horizontalPadding)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(Constants.Colors.surfaceGlass)
        )
    }

    private var statusColor: Color {
        if babelService.isListening {
            return Constants.Colors.electricGreen
        } else if babelService.isTranslating {
            return Constants.Colors.amber
        } else {
            return Constants.Colors.textTertiary
        }
    }

    private var statusText: String {
        if babelService.isListening && !babelService.currentPartialText.isEmpty {
            return "TRANSLATING"
        } else if babelService.isListening {
            return "LISTENING"
        } else if babelService.isTranslating {
            return "SENDING"
        } else {
            return "IDLE"
        }
    }

    // MARK: - Translation Feed

    private var translationFeed: some View {
        Group {
            if babelService.receivedTranslations.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(babelService.receivedTranslations) { message in
                                translationCard(message)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, Constants.Layout.horizontalPadding)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: babelService.receivedTranslations.count) { _, _ in
                        if let last = babelService.receivedTranslations.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Constants.Colors.textTertiary)

            Text("Select languages and tap Start\nto begin translating")
                .font(Constants.Typography.body)
                .foregroundStyle(Constants.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func translationCard(_ message: BabelMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Sender + timestamp
            HStack {
                Text(message.senderName)
                    .font(Constants.Typography.caption)
                    .foregroundStyle(Constants.Colors.amber)

                Spacer()

                Text(message.timestamp, style: .time)
                    .font(Constants.Typography.monoSmall)
                    .foregroundStyle(Constants.Colors.textTertiary)
            }

            // Original text
            HStack(spacing: 6) {
                Text(flagEmoji(for: message.sourceLanguage))
                    .font(.system(size: 12))

                Text(message.originalText)
                    .font(Constants.Typography.body)
                    .foregroundStyle(Constants.Colors.textSecondary)
            }

            // Divider
            Rectangle()
                .fill(Constants.Colors.surfaceBorder)
                .frame(height: 0.5)

            // Translated text
            HStack(spacing: 6) {
                Text(flagEmoji(for: message.targetLanguage))
                    .font(.system(size: 12))

                Text(message.displayText)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Constants.Colors.textPrimary)
            }
        }
        .padding(Constants.Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius)
                .strokeBorder(Constants.Colors.surfaceBorder, lineWidth: Constants.Layout.glassBorderWidth)
        )
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 14) {
            // Auto-speak toggle
            HStack {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(
                        babelService.autoSpeak
                            ? Constants.Colors.electricGreen
                            : Constants.Colors.textTertiary
                    )

                Text("Auto-speak translations")
                    .font(Constants.Typography.caption)
                    .foregroundStyle(Constants.Colors.textSecondary)

                Spacer()

                Toggle("", isOn: $babelService.autoSpeak)
                    .labelsHidden()
                    .tint(Constants.Colors.electricGreen)
            }
            .padding(.horizontal, Constants.Layout.horizontalPadding)

            // Start / Stop button
            Button {
                Task {
                    await toggleTranslation()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: babelService.isTranslating ? "stop.fill" : "waveform")
                        .font(.system(size: 18, weight: .bold))

                    Text(babelService.isTranslating ? "Stop" : "Start Translating")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(
                    babelService.isTranslating ? Constants.Colors.textPrimary : Color.black
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                        .fill(
                            babelService.isTranslating
                                ? Constants.Colors.hotRed
                                : Constants.Colors.amber
                        )
                )
                .shadow(
                    color: (babelService.isTranslating
                        ? Constants.Colors.hotRed
                        : Constants.Colors.amber
                    ).opacity(0.4),
                    radius: 16,
                    y: 4
                )
            }
            .padding(.horizontal, Constants.Layout.horizontalPadding)
            .padding(.bottom, 20)
        }
        .padding(.top, 10)
        .background(
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, Constants.Colors.backgroundPrimary],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Actions

    private func toggleTranslation() async {
        if babelService.isTranslating {
            babelService.stopSession()
        } else {
            guard sourceLanguage != targetLanguage else {
                errorMessage = "Source and target languages must be different."
                showError = true
                return
            }

            let authorized = await babelService.requestAuthorization()
            guard authorized else {
                errorMessage = "Speech recognition permission is required for live translation."
                showError = true
                return
            }

            do {
                try await babelService.startSession(
                    sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage,
                    channelID: channelID,
                    senderID: localPeerID,
                    senderName: localPeerName
                )
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                logger.error("Failed to start Babel session: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Helpers

    private func languageName(for code: String) -> String {
        languages.first(where: { $0.code == code })?.name ?? code
    }

    private func flagEmoji(for languageCode: String) -> String {
        // Map common BCP-47 codes to flag emoji via region
        let regionMap: [String: String] = [
            "en-US": "\u{1F1FA}\u{1F1F8}",
            "es": "\u{1F1EA}\u{1F1F8}",
            "fr": "\u{1F1EB}\u{1F1F7}",
            "de": "\u{1F1E9}\u{1F1EA}",
            "it": "\u{1F1EE}\u{1F1F9}",
            "pt-BR": "\u{1F1E7}\u{1F1F7}",
            "zh-Hans": "\u{1F1E8}\u{1F1F3}",
            "ja": "\u{1F1EF}\u{1F1F5}",
            "ko": "\u{1F1F0}\u{1F1F7}",
            "ar": "\u{1F1F8}\u{1F1E6}",
            "ru": "\u{1F1F7}\u{1F1FA}",
            "hi": "\u{1F1EE}\u{1F1F3}",
            "uk": "\u{1F1FA}\u{1F1E6}",
            "pl": "\u{1F1F5}\u{1F1F1}",
            "tr": "\u{1F1F9}\u{1F1F7}",
        ]
        return regionMap[languageCode] ?? "\u{1F310}"
    }
}
