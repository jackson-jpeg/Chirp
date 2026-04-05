import SwiftUI
import Photos
import OSLog

/// Full-screen image viewer with pinch-to-zoom and save-to-photos.
struct ImagePreviewSheet: View {

    let image: UIImage

    @Environment(\.dismiss) private var dismiss

    @State private var currentZoom: CGFloat = 1.0
    @State private var totalZoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var saveState: SaveState = .idle
    @State private var dragToDismissOffset: CGFloat = 0
    @State private var backgroundOpacity: Double = 1.0
    @State private var showShareSheet: Bool = false

    private let logger = Logger(subsystem: Constants.subsystem, category: "ImagePreview")

    private enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(backgroundOpacity)
                .ignoresSafeArea()

            // Zoomable image with drag-to-dismiss
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(currentZoom * totalZoom)
                .offset(x: offset.width, y: offset.height + dragToDismissOffset)
                .gesture(zoomGesture)
                .gesture(combinedDragGesture)
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if totalZoom > 1.5 {
                            totalZoom = 1.0
                            offset = .zero
                            lastOffset = .zero
                        } else {
                            totalZoom = 3.0
                        }
                    }
                }
                .accessibilityLabel("Full size image preview")

            // Controls overlay
            VStack {
                // Top bar
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(16)
                    }
                    .accessibilityLabel("Close preview")
                }

                Spacer()

                // Bottom bar
                HStack(spacing: 20) {
                    // Share button
                    shareButton

                    saveButton
                }
                .padding(.bottom, 40)
            }
            .opacity(backgroundOpacity)
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheetView(items: [image])
        }
    }

    // MARK: - Gestures

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                currentZoom = value.magnification
            }
            .onEnded { value in
                totalZoom *= value.magnification
                currentZoom = 1.0
                // Clamp zoom
                totalZoom = min(max(totalZoom, 1.0), 5.0)
                if totalZoom <= 1.0 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            }
    }

    /// Combined drag gesture: pans when zoomed in, drag-to-dismiss when at 1x.
    private var combinedDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if totalZoom > 1.0 {
                    // Pan mode
                    offset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                } else {
                    // Drag-to-dismiss mode
                    dragToDismissOffset = value.translation.height
                    let progress = min(abs(value.translation.height) / 300, 1.0)
                    backgroundOpacity = 1.0 - progress * 0.6
                }
            }
            .onEnded { value in
                if totalZoom > 1.0 {
                    lastOffset = offset
                } else {
                    if abs(value.translation.height) > 120 {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragToDismissOffset = 0
                            backgroundOpacity = 1.0
                        }
                    }
                }
            }
    }

    // MARK: - Share Button

    private var shareButton: some View {
        Button {
            showShareSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                Text("Share")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.15))
            .clipShape(Capsule())
        }
        .accessibilityLabel("Share image")
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button {
            saveToPhotos()
        } label: {
            HStack(spacing: 8) {
                switch saveState {
                case .idle:
                    Image(systemName: "square.and.arrow.down")
                    Text("Save to Photos")
                case .saving:
                    ProgressView()
                        .tint(.white)
                    Text("Saving...")
                case .saved:
                    Image(systemName: "checkmark.circle.fill")
                    Text("Saved")
                case .failed(let reason):
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(reason)
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(saveState == .saved ? Constants.Colors.electricGreen : .white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.15))
            .clipShape(Capsule())
        }
        .disabled(saveState == .saving || saveState == .saved)
        .accessibilityLabel("Save image to photo library")
    }

    // MARK: - Save

    private func saveToPhotos() {
        saveState = .saving

        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)

            guard status == .authorized || status == .limited else {
                await MainActor.run {
                    saveState = .failed("No permission")
                    logger.warning("Photo library access denied")
                }
                return
            }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: image.jpegData(compressionQuality: 0.9) ?? Data(), options: nil)
                }
                await MainActor.run {
                    saveState = .saved
                    logger.info("Image saved to photo library")
                }
            } catch {
                await MainActor.run {
                    saveState = .failed("Save failed")
                    logger.error("Failed to save image: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}

// MARK: - Share Sheet

/// UIKit share sheet wrapper for sharing arbitrary items.
private struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
