import Foundation
import Photos
import Vision
import UIKit
import ShoeboxCore

/// Moment 5: a screenshot is a save. New screenshots are read on the phone; one that holds a date, an address,
/// a form or a list is kept, and comes back by the date it found. Others are left alone. Nothing is sent.
/// [Check] The spec says "offered as a save"; here it is kept and its moment is the offer (Drop says no).
@MainActor
enum Screenshots {
    static var on: Bool { AppGroup.defaults.bool(forKey: "shoebox.screenshots") }

    static func turnOn() async -> Bool {
        let s = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        let ok = s == .authorized || s == .limited
        AppGroup.defaults.set(ok, forKey: "shoebox.screenshots")
        if ok { AppGroup.defaults.set(Date.now.timeIntervalSince1970, forKey: "shoebox.screenshotsSince") }
        return ok
    }

    static func turnOff() { AppGroup.defaults.set(false, forKey: "shoebox.screenshots") }

    @discardableResult
    static func check(keeper: Keeper) async -> Int {
        guard on else { return 0 }
        let since = Date(timeIntervalSince1970: AppGroup.defaults.double(forKey: "shoebox.screenshotsSince"))
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0 AND creationDate > %@",
                                     PHAssetMediaSubtype.photoScreenshot.rawValue, since as NSDate)
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = PHAsset.fetchAssets(with: .image, options: opts)
        var list: [PHAsset] = []
        assets.enumerateObjects { a, _, _ in list.append(a) }
        var kept = 0
        let events = CalendarReader.upcoming()
        for a in list.prefix(10) {
            AppGroup.defaults.set((a.creationDate ?? .now).timeIntervalSince1970, forKey: "shoebox.screenshotsSince")
            guard let data = await imageData(a), let text = await read(data), let found = Finder.worthKeeping(text) else { continue }
            var draft = Detection.Draft(kind: .photo, title: found.title)
            draft.text = nil
            let (s, _) = keeper.keep(draft, reason: "", reasonSource: .none, source: .screenshot,
                                     files: [(data, "image/jpeg", "screenshot.jpg")], events: events)
            s.transcript = String(text.prefix(1500))
            if let when = found.when { keeper.plan(s, events: events, reasonText: when) }
            try? keeper.context.save()
            kept += 1
        }
        return kept
    }

    private static func imageData(_ a: PHAsset) async -> Data? {
        await withCheckedContinuation { c in
            let o = PHImageRequestOptions()
            o.isNetworkAccessAllowed = false
            o.deliveryMode = .highQualityFormat
            o.isSynchronous = false
            PHImageManager.default().requestImage(for: a, targetSize: CGSize(width: 1600, height: 1600), contentMode: .aspectFit, options: o) { img, info in
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                c.resume(returning: img?.jpegData(compressionQuality: 0.82))
            }
        }
    }

    private static func read(_ data: Data) async -> String? {
        await Task.detached(priority: .utility) { () -> String? in
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = true
            do { try VNImageRequestHandler(data: data).perform([req]) } catch { return nil }
            let lines = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        }.value
    }

    enum Finder {
        struct Found { var title: String; var when: String? }

        /// A date, an address, a form or a list: worth keeping. Anything else is left alone.
        static func worthKeeping(_ text: String) -> Found? {
            let types: NSTextCheckingResult.CheckingType = [.date, .address]
            let detector = try? NSDataDetector(types: types.rawValue)
            let range = NSRange(text.startIndex..., in: text)
            let matches = detector?.matches(in: text, range: range) ?? []
            let date = matches.first { $0.resultType == .date && ($0.date ?? .distantPast) > .now }
            let hasAddress = matches.contains { $0.resultType == .address }
            let lower = text.lowercased()
            let form = ["sign up", "register", "rsvp", "permission slip", "due", "deadline", "form"].contains { lower.contains($0) }
            let lines = text.split(separator: "\n")
            let list = lines.filter { $0.hasPrefix("•") || $0.hasPrefix("-") || $0.first?.isNumber == true && $0.dropFirst().hasPrefix(".") }.count >= 3
            guard date != nil || hasAddress || form || list else { return nil }
            let title = lines.map { $0.trimmingCharacters(in: .whitespaces) }.first { $0.count > 6 && $0.count < 90 } ?? "Screenshot"
            var when: String?
            if let d = date?.date {
                let words = d.formatted(.dateTime.month(.abbreviated).day())
                when = (form ? "by " : "") + words
            }
            return Found(title: String(title), when: when)
        }
    }
}
