import ImageIO
import Observation
import SwiftUI
import UIKit

/// Where the Shoebox sheet is as it slides out from behind the box on Today: 0 hidden, 1 fully open.
/// It lives in its own object so that moving it redraws only the sheet, the dim behind it and the box,
/// never the whole Today screen with every post and rule behind it. That is what keeps the pull smooth.
@Observable
final class BoxPull {
    var progress: CGFloat = 0
    /// The sheet is built once, shortly after Today appears, and kept, so the first pull has nothing to build.
    var mounted = false
    var dragging = false
    var start: CGFloat = 0
    /// Counts closings, so the Shoebox can hand a showing Undo to Today.
    var closedTick = 0
}

/// Slides the sheet: its top follows `progress` between hidden behind the box and just under the status bar.
struct BoxSheetOffset: ViewModifier {
    let pull: BoxPull
    let closed: CGFloat
    let open: CGFloat

    func body(content: Content) -> some View {
        content.offset(y: closed + (open - closed) * pull.progress)
    }
}

/// The box fades out as the sheet arrives, and stops taking touches once it is fully open.
struct BoxStripFade: ViewModifier {
    let pull: BoxPull

    func body(content: Content) -> some View {
        content
            .opacity(1 - Double(min(1, max(0, (pull.progress - 0.55) / 0.45))))
            .allowsHitTesting(pull.progress < 0.98 || pull.dragging)
    }
}

/// Today dims as the sheet rises.
struct BoxDim: View {
    let pull: BoxPull

    var body: some View {
        Color.black.opacity(0.4 * pull.progress).ignoresSafeArea().allowsHitTesting(false)
    }
}

/// Small pictures for the Shoebox list, made once at the size they are shown and kept.
/// Decoding a full picture for every row while the sheet comes out is what made it hesitate.
enum Thumbs {
    private static let cache = NSCache<NSString, UIImage>()

    static func cached(_ id: UUID) -> UIImage? { cache.object(forKey: id.uuidString as NSString) }

    static func load(id: UUID, data: Data) async -> UIImage? {
        if let hit = cached(id) { return hit }
        let image = await Task.detached(priority: .utility) { () -> UIImage? in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 160,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
        }.value
        if let image { cache.setObject(image, forKey: id.uuidString as NSString) }
        return image
    }
}

/// The small tile at the left of a row: the post's own picture, or the warm Onyx tile when it has none.
struct RowThumb: View {
    let save: Save
    @State private var image: UIImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        ZStack {
            if let image = image ?? Thumbs.cached(save.id) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                shape.fill(Theme.card)
                RadialGradient(colors: [Theme.lid.opacity(0.45), .clear], center: .topLeading, startRadius: 0, endRadius: 46)
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(shape)
        .task(id: save.id) {
            guard image == nil, Thumbs.cached(save.id) == nil, let data = save.imageData else { return }
            image = await Thumbs.load(id: save.id, data: data)
        }
    }
}
