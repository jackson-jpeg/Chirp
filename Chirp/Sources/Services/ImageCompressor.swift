import UIKit
import OSLog

/// Compresses and resizes images for transmission over the mesh network.
///
/// Images are resized to fit within a maximum dimension (400x400 by default)
/// while maintaining aspect ratio, then JPEG-compressed at decreasing quality
/// until the result fits within the payload budget. EXIF metadata is stripped
/// automatically by ``UIGraphicsImageRenderer``.
enum ImageCompressor {

    private static let logger = Logger(subsystem: Constants.subsystem, category: "ImageCompressor")

    /// Maximum dimension (width or height) for the resized image.
    private static let maxDimension: CGFloat = 400

    /// Target maximum size in bytes for the compressed JPEG.
    private static let maxBytes = 50_000

    /// Resize and compress a ``UIImage`` to a JPEG within ``maxBytes``.
    ///
    /// - Parameter image: The source image.
    /// - Returns: Compressed JPEG data, or `nil` if compression fails entirely.
    static func compress(_ image: UIImage) -> Data? {
        let resized = resizeToFit(image)

        // Try decreasing quality levels until we fit the budget.
        let qualitySteps: [CGFloat] = [0.7, 0.5, 0.35, 0.2, 0.1, 0.05]

        for quality in qualitySteps {
            let renderer = UIGraphicsImageRenderer(size: resized.size)
            let data = renderer.jpegData(withCompressionQuality: quality) { ctx in
                resized.draw(in: CGRect(origin: .zero, size: resized.size))
            }

            if data.count <= maxBytes {
                logger.info("Compressed image to \(data.count) bytes at quality \(quality, format: .fixed(precision: 2))")
                return data
            }
        }

        // Last resort: smallest quality
        let renderer = UIGraphicsImageRenderer(size: resized.size)
        let data = renderer.jpegData(withCompressionQuality: 0.01) { ctx in
            resized.draw(in: CGRect(origin: .zero, size: resized.size))
        }

        if data.count <= maxBytes {
            logger.info("Compressed image to \(data.count) bytes at minimum quality")
            return data
        }

        logger.error("Failed to compress image below \(maxBytes) bytes (got \(data.count))")
        return nil
    }

    /// Compress an image for file transfer with configurable limits.
    ///
    /// - Parameters:
    ///   - image: The source image.
    ///   - maxBytes: Maximum output size in bytes (default 500 KB).
    ///   - maxDimension: Maximum width or height in points (default 1200).
    /// - Returns: Compressed JPEG data, or `nil` if compression fails.
    static func compressForTransfer(
        _ image: UIImage,
        maxBytes: Int = 500_000,
        maxDimension: CGFloat = 1200
    ) -> Data? {
        let resized = resizeToFit(image, maxDimension: maxDimension)

        let qualitySteps: [CGFloat] = [0.8, 0.65, 0.5, 0.35, 0.2, 0.1, 0.05]

        for quality in qualitySteps {
            let renderer = UIGraphicsImageRenderer(size: resized.size)
            let data = renderer.jpegData(withCompressionQuality: quality) { ctx in
                resized.draw(in: CGRect(origin: .zero, size: resized.size))
            }

            if data.count <= maxBytes {
                logger.info("Compressed image for transfer to \(data.count) bytes at quality \(quality, format: .fixed(precision: 2))")
                return data
            }
        }

        // Last resort
        let renderer = UIGraphicsImageRenderer(size: resized.size)
        let data = renderer.jpegData(withCompressionQuality: 0.01) { ctx in
            resized.draw(in: CGRect(origin: .zero, size: resized.size))
        }

        if data.count <= maxBytes {
            logger.info("Compressed image for transfer to \(data.count) bytes at minimum quality")
            return data
        }

        logger.error("Failed to compress image for transfer below \(maxBytes) bytes (got \(data.count))")
        return nil
    }

    // MARK: - Private

    /// Resize the image so its longest side fits within ``maxDimension``,
    /// preserving aspect ratio. Returns the original if already small enough.
    private static func resizeToFit(_ image: UIImage) -> UIImage {
        resizeToFit(image, maxDimension: maxDimension)
    }

    /// Resize the image so its longest side fits within the given dimension,
    /// preserving aspect ratio. Returns the original if already small enough.
    private static func resizeToFit(_ image: UIImage, maxDimension limit: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > limit || size.height > limit else {
            return image
        }

        let scale: CGFloat
        if size.width >= size.height {
            scale = limit / size.width
        } else {
            scale = limit / size.height
        }

        let newSize = CGSize(
            width: (size.width * scale).rounded(.down),
            height: (size.height * scale).rounded(.down)
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
