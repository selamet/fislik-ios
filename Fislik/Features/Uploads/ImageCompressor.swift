import UIKit
import UniformTypeIdentifiers

/// Mirrors the web client: images become JPEG ≤2000px, ~1MB; PDFs are untouched.
enum ImageCompressor {
    static let maxDimension: CGFloat = 2000
    static let targetBytes = 1_000_000
    static let maxUploadBytes = 15 * 1024 * 1024

    static func jpeg(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return jpeg(from: image)
    }

    static func jpeg(from image: UIImage) -> Data? {
        let scaled = resized(image)
        var quality: CGFloat = 0.85
        var out = scaled.jpegData(compressionQuality: quality)
        while let d = out, d.count > targetBytes, quality > 0.4 {
            quality -= 0.1
            out = scaled.jpegData(compressionQuality: quality)
        }
        return out
    }

    private static func resized(_ image: UIImage) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return normalized(image) }
        let scale = maxDimension / longest
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Bakes EXIF orientation into pixels.
    private static func normalized(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
