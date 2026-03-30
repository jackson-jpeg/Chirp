import SwiftUI

/// Renders an image attachment inside a message bubble.
///
/// Decodes the base64 payload (after stripping the `IMG:` prefix) and shows
/// a rounded thumbnail. Tapping the thumbnail opens a full-screen preview.
/// Follows the same visual pattern as ``LocationAttachmentView``: amber accent,
/// rounded corners, white 0.08 opacity background.
struct ImageAttachmentView: View {

    let text: String

    @State private var showPreview = false

    private var imageData: Data? {
        let payload: String
        if text.hasPrefix(MeshTextMessage.imagePrefix) {
            payload = String(text.dropFirst(MeshTextMessage.imagePrefix.count))
        } else {
            payload = text
        }
        return Data(base64Encoded: payload)
    }

    private var uiImage: UIImage? {
        guard let data = imageData else { return nil }
        return UIImage(data: data)
    }

    private var dimensionText: String? {
        guard let img = uiImage else { return nil }
        let w = Int(img.size.width * img.scale)
        let h = Int(img.size.height * img.scale)
        return "\(w) x \(h)"
    }

    private var sizeText: String? {
        guard let data = imageData else { return nil }
        let kb = Double(data.count) / 1024.0
        return String(format: "%.1f KB", kb)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "photo.fill")
                    .foregroundStyle(Constants.Colors.amber)
                    .font(.title3)
                Text("Shared Image")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Constants.Colors.amber)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Shared image")

            // Thumbnail
            if let image = uiImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 240, maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onTapGesture { showPreview = true }
                    .accessibilityLabel("Image thumbnail, tap to preview")
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Constants.Colors.hotRed)
                    Text("Unable to decode image")
                        .font(.caption)
                        .foregroundStyle(Constants.Colors.textSecondary)
                }
            }

            // Metadata row
            if let dims = dimensionText, let size = sizeText {
                HStack(spacing: 8) {
                    Text(dims)
                        .font(Constants.Typography.badge)
                        .foregroundStyle(Constants.Colors.textSecondary)
                    Text(size)
                        .font(Constants.Typography.badge)
                        .foregroundStyle(Constants.Colors.textTertiary)
                }
            }
        }
        .padding(12)
        .background(Constants.Colors.surfaceGlass)
        .clipShape(RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius)
                .strokeBorder(Constants.Colors.glassAmberBorder.opacity(0.5), lineWidth: Constants.Layout.glassBorderWidth)
        )
        .fullScreenCover(isPresented: $showPreview) {
            if let image = uiImage {
                ImagePreviewSheet(image: image)
            }
        }
    }
}
