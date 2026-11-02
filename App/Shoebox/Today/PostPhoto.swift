import SwiftUI
import UIKit
import Vision

/// How a photo is graded so any picture sits well under the words: a bright one is toned down, a dark or
/// flat one is lifted, and the shading and glass behind the words get stronger as the picture gets brighter
/// where the words sit. Worked out once per picture from a 16 by 16 copy.
struct PhotoGrade: Equatable {
    /// The plum shade laid over the picture, 0 to 1.
    var wash: Double
    var lift: Double
    var saturation: Double
    var contrast: Double
    /// How dark the shading at the bottom gets, where the words sit.
    var scrim: Double
    /// How much the plum shade tints the glass behind the words.
    var glassTint: Double

    static let neutral = PhotoGrade(wash: 0.12, lift: 0, saturation: 1.04, contrast: 1.04, scrim: 0.55, glassTint: 0.28)
    /// A post with no picture: dark already, so the glass needs little.
    static let none = PhotoGrade(wash: 0, lift: 0, saturation: 1, contrast: 1, scrim: 0.4, glassTint: 0.22)

    static func make(from image: UIImage) -> PhotoGrade {
        guard let stats = Stats(image) else { return .neutral }
        let mean = stats.mean
        // 0 for a dark lower half, 1 for a bright one.
        let brightBelow = min(1, max(0, (stats.lowerMean - 0.22) / 0.5))
        return PhotoGrade(
            wash: min(0.44, 0.10 + max(0, mean - 0.38) * 0.95),
            lift: mean < 0.25 ? 0.05 : 0,
            saturation: mean > 0.72 ? 0.9 : 1.06,
            contrast: stats.spread < 0.14 ? 1.12 : 1.04,
            scrim: 0.46 + 0.34 * brightBelow,
            glassTint: 0.26 + 0.30 * brightBelow
        )
    }

    /// Mean and spread of brightness, and the mean of the lower part where the words sit.
    private struct Stats {
        let mean: Double
        let spread: Double
        let lowerMean: Double

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
            // Row 0 of the buffer is the top of the picture; the words sit over the lower 45%.
            let lower = Array(lumas[(side * 9)...])
            mean = m
            spread = variance.squareRoot()
            lowerMean = lower.reduce(0, +) / Double(lower.count)
        }
    }
}

/// Where the subject of a picture is: faces first, then whatever the eye goes to. Runs on the phone.
enum FocusFinder {
    /// A point in the picture, 0 to 1 from the left and from the top.
    static func find(in image: UIImage) -> CGPoint {
        let fallback = CGPoint(x: 0.5, y: 0.42)
        guard let cg = image.cgImage else { return fallback }
        let faces = VNDetectFaceRectanglesRequest()
        let attention = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: CGImagePropertyOrientation(image.imageOrientation), options: [:])
        try? handler.perform([faces, attention])

        // Vision's origin is the bottom left; ours is the top left.
        if let found = faces.results, !found.isEmpty {
            var union = found[0].boundingBox
            for f in found.dropFirst() { union = union.union(f.boundingBox) }
            return CGPoint(x: union.midX, y: 1 - union.midY)
        }
        if let obs = attention.results?.first, let box = obs.salientObjects?.first?.boundingBox {
            return CGPoint(x: box.midX, y: 1 - box.midY)
        }
        return fallback
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// Decoded pictures, their grades and focus points, kept so scrolling never decodes twice.
enum PhotoCache {
    final class Entry {
        let image: UIImage
        let grade: PhotoGrade
        init(_ image: UIImage, _ grade: PhotoGrade) { self.image = image; self.grade = grade }
    }
    private final class Point { let value: CGPoint; init(_ v: CGPoint) { value = v } }

    private static let entries = NSCache<NSString, Entry>()
    private static let points = NSCache<NSString, Point>()

    private static func key(_ id: UUID, _ data: Data) -> NSString { "\(id.uuidString)-\(data.count)" as NSString }

    static func entry(id: UUID, data: Data) -> Entry? {
        let k = key(id, data)
        if let hit = entries.object(forKey: k) { return hit }
        guard let image = UIImage(data: data) else { return nil }
        let entry = Entry(image, PhotoGrade.make(from: image))
        entries.setObject(entry, forKey: k)
        return entry
    }

    /// The grade for a post's picture, for the words that sit on it.
    static func grade(id: UUID, data: Data?) -> PhotoGrade {
        guard let data, let e = entry(id: id, data: data) else { return .none }
        return e.grade
    }

    /// The focus point, found once off the main thread.
    static func focus(id: UUID, data: Data) async -> CGPoint? {
        let k = key(id, data)
        if let hit = points.object(forKey: k) { return hit.value }
        guard let image = entry(id: id, data: data)?.image else { return nil }
        let p = await Task.detached(priority: .utility) { FocusFinder.find(in: image) }.value
        points.setObject(Point(p), forKey: k)
        return p
    }
}

/// The picture behind a post, full bleed. It is graded (toned down when bright, lifted when dark or flat),
/// washed with a little plum shade and Plum so every photo belongs to the same app, shaded so the status bar and the
/// glass stay readable, and framed so the subject sits in the clear space above the words.
/// With no picture it is Plum Night lit warm from the top corner.
struct PostPhoto: View {
    let id: UUID
    let data: Data?
    /// Space at the top taken by buttons, and at the bottom by the words and the box. The subject is centered between.
    var topClear: CGFloat = 110
    var bottomClear: CGFloat = 330

    @State private var focus = CGPoint(x: 0.5, y: 0.42)

    var body: some View {
        let entry = data.flatMap { PhotoCache.entry(id: id, data: $0) }
        ZStack {
            if let entry {
                // The picture sits in an overlay so its size never changes the size of the card.
                Color.clear
                    .overlay {
                        GeometryReader { geo in
                            framed(entry.image, entry.grade, in: geo.size)
                        }
                    }
                    .clipped()
                Theme.shade.opacity(entry.grade.wash)
                Theme.plum.opacity(0.30).blendMode(.softLight)
                // Darker toward the edges, so the middle of the picture leads.
                RadialGradient(colors: [.clear, Theme.shade.opacity(0.32)],
                               center: .center, startRadius: 160, endRadius: 560)
            } else {
                // No picture: Plum Night lit warm from the top corner, so the words have something to sit on.
                ZStack {
                    Theme.plumNight
                    RadialGradient(colors: [Theme.lid.opacity(0.30), Theme.lid.opacity(0.06), .clear],
                                   center: .topLeading, startRadius: 0, endRadius: 620)
                }
            }
            let scrim = entry?.grade.scrim ?? PhotoGrade.none.scrim
            LinearGradient(stops: [.init(color: Theme.shade.opacity(0.30), location: 0),
                                   .init(color: .clear, location: 0.22),
                                   .init(color: .clear, location: 0.42),
                                   .init(color: Theme.shade.opacity(scrim), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .task(id: "\(id.uuidString)-\(data?.count ?? 0)") {
            guard let data, let p = await PhotoCache.focus(id: id, data: data) else { return }
            withAnimation(.easeOut(duration: 0.35)) { focus = p }
        }
        .accessibilityHidden(true)
    }

    /// Fill the screen, with the focus point as near the middle of the clear space as the picture's edges allow.
    private func framed(_ image: UIImage, _ grade: PhotoGrade, in size: CGSize) -> some View {
        let iw = max(image.size.width, 1), ih = max(image.size.height, 1)
        let scale = max(size.width / iw, size.height / ih)
        let w = iw * scale, h = ih * scale
        let targetY = topClear + max(0, size.height - topClear - bottomClear) / 2
        let x = min(0, max(size.width - w, size.width / 2 - focus.x * w))
        let y = min(0, max(size.height - h, targetY - focus.y * h))
        return Image(uiImage: image)
            .resizable()
            .frame(width: w, height: h)
            .saturation(grade.saturation)
            .contrast(grade.contrast)
            .brightness(grade.lift)
            .offset(x: x, y: y)
    }
}
