import MetalKit
import SwiftUI
import OSLog

/// Secure view-once photo viewer using Metal rendering.
///
/// Displays a decrypted photo directly via an ``MTKView`` to minimize time
/// decrypted pixels spend in addressable memory. Monitors for screenshot
/// and screen recording attempts, immediately dismissing and securely wiping
/// on detection.
struct DarkroomViewerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let envelopeID: UUID

    @State private var renderer: DarkroomRenderer?
    @State private var imageData: Data?
    @State private var isLoaded = false
    @State private var openDuration: TimeInterval = 0
    @State private var screenshotDetected = false
    @State private var showScreenshotAlert = false
    @State private var showError = false
    @State private var errorMessage = ""

    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private let logger = Logger(subsystem: Constants.subsystem, category: "DarkroomViewer")

    // MARK: - Body

    var body: some View {
        ZStack {
            // Pure black background
            Color.black
                .ignoresSafeArea()

            if isLoaded, let renderer {
                // Metal rendered photo
                MetalViewRepresentable(renderer: renderer)
                    .ignoresSafeArea()
            } else if isLoaded {
                // Fallback: UIImage display if Metal failed
                if let imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .ignoresSafeArea()
                }
            } else {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(Constants.Colors.amber)
                    Text("Decrypting...")
                        .font(Constants.Typography.mono)
                        .foregroundStyle(Constants.Colors.textSecondary)
                }
            }

            // Overlay UI
            VStack {
                // Top bar
                HStack {
                    // Timer
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Constants.Colors.hotRed)
                            .frame(width: 8, height: 8)

                        Text(formatDuration(openDuration))
                            .font(Constants.Typography.monoStatus)
                            .foregroundStyle(Constants.Colors.hotRed)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .environment(\.colorScheme, .dark)
                    )

                    Spacer()

                    // Close button
                    Button {
                        closeAndWipe()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Constants.Colors.textPrimary)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .environment(\.colorScheme, .dark)
                                    .frame(width: 32, height: 32)
                            )
                    }
                }
                .padding(.horizontal, Constants.Layout.horizontalPadding)
                .padding(.top, 8)

                Spacer()

                // Bottom warning
                VStack(spacing: 8) {
                    // Screenshot warning overlay
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Constants.Colors.hotRed)

                        Text("Screenshots are detected and reported")
                            .font(Constants.Typography.caption)
                            .foregroundStyle(Constants.Colors.hotRed)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Constants.Colors.glassRed)
                    )

                    // Self-destruct notice
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 12))
                        Text("This photo will be deleted when you close it")
                            .font(Constants.Typography.caption)
                    }
                    .foregroundStyle(Constants.Colors.textSecondary)
                }
                .padding(.bottom, 40)
            }
        }
        .statusBarHidden()
        .onAppear {
            decryptAndLoad()
            startScreenshotDetection()
        }
        .onDisappear {
            appState.darkroomService.stopScreenshotDetection()
            if isLoaded {
                closeAndWipe()
            }
        }
        .onReceive(timer) { _ in
            if isLoaded {
                openDuration += 0.1
            }
        }
        .alert("Screenshot Detected", isPresented: $showScreenshotAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("A screenshot was captured. The sender has been notified and the photo has been securely deleted.")
        }
        .alert("Decryption Failed", isPresented: $showError) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Decryption

    private func decryptAndLoad() {
        // In production, the recipient's key-agreement private key would come
        // from PeerIdentity. For now we attempt decryption with PeerIdentity.
        Task {
            do {
                let privateKey = await PeerIdentity.shared.getKeyAgreementPrivateKey()
                let (data, metalRenderer) = try appState.darkroomService.viewPhoto(
                    envelopeID: envelopeID,
                    privateKey: privateKey
                )
                self.imageData = data
                self.renderer = metalRenderer
                self.isLoaded = true
                logger.info("Darkroom photo loaded for \(envelopeID)")
            } catch {
                errorMessage = "Failed to decrypt photo: \(error.localizedDescription)"
                showError = true
                logger.error("Failed to decrypt darkroom photo: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Screenshot Detection

    private func startScreenshotDetection() {
        appState.darkroomService.startScreenshotDetection { [self] in
            Task { @MainActor in
                self.screenshotDetected = true
                self.showScreenshotAlert = true
                self.logger.warning("Screenshot detected — closing viewer")
            }
        }
    }

    // MARK: - Close

    private func closeAndWipe() {
        guard isLoaded else { return }
        appState.darkroomService.closeViewing(envelopeID: envelopeID)
        renderer = nil
        imageData = nil
        isLoaded = false
        logger.info("Darkroom viewer closed — secure wipe complete")
        dismiss()
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let tenths = Int((seconds - Double(Int(seconds))) * 10)
        return String(format: "%d:%02d.%d", mins, secs, tenths)
    }
}

// MARK: - Metal View Representable

/// Wraps an ``MTKView`` driven by a ``DarkroomRenderer`` for use in SwiftUI.
private struct MetalViewRepresentable: UIViewRepresentable {
    let renderer: DarkroomRenderer

    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = renderer
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = true
        mtkView.preferredFramesPerSecond = 30
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.backgroundColor = .black
        // Disable user interaction to prevent gesture interference
        mtkView.isUserInteractionEnabled = false
        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        // Renderer state is managed externally
    }
}
