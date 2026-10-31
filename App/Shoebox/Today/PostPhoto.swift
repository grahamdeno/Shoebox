import SwiftUI
import UIKit

/// How a photo is graded so any picture sits well under the words: a bright one is
/// toned down, a dark or flat one is lifted. Worked out once per picture from its
/// average brightness and spread.
struct PhotoGrade: Equatable {
    /// Onyx laid over the picture, 0 to 1.
    var wash: Double
    var lift: Double
    var saturation: Double
    var contrast: Double

    static let neutral = PhotoGrade(wash: 0.12, lift: 0, saturation: 1.04, contrast: 1.04)

    static func make(from image: UIImage) -> PhotoGrade {
        guard let stats = Stats(image) else { return .neutral }
        let mean = stats.mean
        let spread = stats.spread
        return PhotoGrade(
            // Nothing over a dark picture beyond the base; more and more over a bright one.
            wash: min(0.44, 0.10 + max(0, mean - 0.38) * 0.95),
            lift: mean < 0.25 ? 0.05 : 0,
            saturation: mean > 0.72 ? 0.9 : 1.06,
            contrast: spread < 0.14 ? 1.12 : 1.04
        )
    }

    /// Mean and spread of brightness, read from a 16 by 16 copy of the picture.
    private struct Stats {
        let mean: Double
        let spread: Double

        init?(_ image: UIImage) {
            guard let cg = image.cgImage else { return nil }
            let side = 16
            var pixels = [UInt8](repeating: 0, count: side * side * 4)
            let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard let ctx = CGContext(
                    data: buffer.baseAddress, width: side, height: side,
                    bitsPerComponent: 8, bytesPerRow: side * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                ctx.interpolationQuality = .medium
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
                return true
            }
            guard drawn else { return nil }
            var lumas: [Double] = []
            lumas.reserveCapacity(side * side)
            for i in stride(from: 0, to: pixels.count, by: 4) {
                let r = Double(pixels[i]) / 255
                let g = Double(pixels[i + 1]) / 255
                let b = Double(pixels[i + 2]) / 255
                lumas.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
            }
            let m = lumas.reduce(0, +) / Double(lumas.count)
            let variance = lumas.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(lumas.count)
            mean = m
            spread = variance.squareRoot()
        }
    }
}

/// Decoded pictures and their grades, kept so scrolling never decodes twice.
private enum PhotoCache {
    final class Entry { let image: UIImage; let grade: PhotoGrade
        init(_ image: UIImage, _ grade: PhotoGrade) { self.image = image; self.grade = grade } }

    private static let cache = NSCache<NSString, Entry>()

    static func entry(id: UUID, data: Data) -> Entry? {
        let key = "\(id.uuidString)-\(data.count)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = UIImage(data: data) else { return nil }
        let entry = Entry(image, PhotoGrade.make(from: image))
        cache.setObject(entry, forKey: key)
        return entry
    }
}

/// The picture behind a post, full bleed. It is graded (toned down when bright, lifted
/// when dark or flat), washed with a little Onyx and Oceanic so every photo belongs to
/// the same app, and shaded top and bottom so the status bar and the glass stay readable.
/// With no picture it is Onyx lit warm from the top corner.
struct PostPhoto: View {
    let id: UUID
    let data: Data?

    var body: some View {
        let entry = data.flatMap { PhotoCache.entry(id: id, data: $0) }
        ZStack {
            if let entry {
                // The picture sits in an overlay so its size never changes the size of the card.
                Color.clear
                    .overlay {
                        Image(uiImage: entry.image)
                            .resizable()
                            .scaledToFill()
                            .saturation(entry.grade.saturation)
                            .contrast(entry.grade.contrast)
                            .brightness(entry.grade.lift)
                    }
                    .clipped()
                Theme.onyx.opacity(entry.grade.wash)
                Theme.oceanic.opacity(0.30).blendMode(.softLight)
                // Darker toward the edges, so the middle of the picture leads.
                RadialGradient(colors: [.clear, .black.opacity(0.32)],
                               center: .center, startRadius: 160, endRadius: 560)
            } else {
                // No picture: Onyx lit warm from the top corner, so the words have something to sit on.
                ZStack {
                    Theme.onyx
                    RadialGradient(colors: [Theme.lid.opacity(0.30), Theme.lid.opacity(0.06), .clear],
                                   center: .topLeading, startRadius: 0, endRadius: 620)
                }
            }
            LinearGradient(colors: [.black.opacity(0.30), .clear, .clear, .black.opacity(0.58)],
                           startPoint: .top, endPoint: .bottom)
        }
        .accessibilityHidden(true)
    }
}
