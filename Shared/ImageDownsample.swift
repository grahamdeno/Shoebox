import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Shrinks a picture while reading it, so the full-size picture is never decoded in memory.
/// A 48 megapixel photo is about 190 MB decoded; the share sheet may only use about 120 MB.
/// ImageIO reads straight from the file or bytes and builds the small version in one step.
enum ImageDownsample {
    /// The picture's size in pixels, read from its header without decoding it.
    static func pixelSize(of source: CGImageSource) -> (width: Int, height: Int)? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0 else { return nil }
        return (w, h)
    }

    /// The longest side to use so that the picture is `width` pixels wide at most (the way pictures were sized
    /// before), whichever way it is turned. Never larger than the picture itself.
    static func longestSide(width: Int, height: Int, maxWidth: Int) -> Int {
        let scale = min(1.0, Double(maxWidth) / Double(width))
        return max(1, Int((Double(max(width, height)) * scale).rounded()))
    }

    /// A smaller picture, turned upright. `maxPixel` is the longest side.
    static func cgImage(source: CGImageSource, maxPixel: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func cgImage(from data: Data, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return cgImage(source: source, maxPixel: maxPixel)
    }

    static func jpeg(_ image: CGImage, quality: CGFloat) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    /// A JPEG of the picture at `url` (a file on disk), its longest side at most `maxPixel`.
    static func jpeg(fromFile url: URL, maxPixel: Int = 2400, quality: CGFloat = 0.85) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = cgImage(source: source, maxPixel: maxPixel) else { return nil }
        return jpeg(image, quality: quality)
    }

    /// A JPEG of the picture in `data`, at most `maxWidth` pixels wide. Nil when it is not a picture, or smaller
    /// than `minimum` (icons and logos).
    static func jpeg(from data: Data, maxWidth: Int, minimum: (width: Int, height: Int)? = nil, quality: CGFloat = 0.8) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let size = pixelSize(of: source) else { return nil }
        if let minimum, size.width < minimum.width || size.height < minimum.height { return nil }
        guard let image = cgImage(source: source, maxPixel: longestSide(width: size.width, height: size.height, maxWidth: maxWidth)) else { return nil }
        return jpeg(image, quality: quality)
    }
}
