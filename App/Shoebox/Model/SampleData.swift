import Foundation
import SwiftData
import UIKit

#if DEBUG
/// Saves for the simulator and screenshots (`-demo YES`). In memory only; never ships in a release build.
enum SampleData {
    static func seed(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Save>())) ?? 0
        guard count == 0 else { return }
        let now = Date()
        let day: TimeInterval = 86_400
        let event = Calendar.current.date(byAdding: .day, value: 12, to: now)

        let trail = Save(title: "A trail worth the drive", snippet: "Coastal loop, 4 miles, about 2 hours away. A lookout halfway and a beach at the end.",
                         body: "A 4 mile coastal loop with a lookout halfway. Parking fills by 9 on weekends, so go early. The trailhead parking details are at https://example.com/trail/parking.",
                         note: "Take the kids in the fall", origin: "Safari", kind: .link,
                         urlString: "https://example.com/trail", createdAt: now - 14 * day)
        trail.imageData = Self.picture(top: 0x6E8392, bottom: 0x3F5566, accent: 0xE8D9B5)
        let teams = Save(title: "Why small teams ship faster", snippet: "Three habits that cut handoffs in half.",
                         body: "Small teams ship faster because they hand off less. Three habits help: one owner per outcome, decisions written down the day they're made, and demos every week.",
                         note: "Read before Monday", origin: "Safari", kind: .link,
                         urlString: "https://example.com/teams", createdAt: now - 9 * day)
        teams.imageData = Self.picture(top: 0x9C826B, bottom: 0x5E4B3C, accent: 0xF2E3CF)
        let pictureDay = Save(title: "Picture day is Nov 12", snippet: "Order forms are due the week before. Retakes are in December.",
                           body: "Picture day is Thursday, November 12. Order forms are due the week before. Retakes are in December.",
                           origin: "via the school newsletter email", kind: .email,
                           eventDate: event, createdAt: now - 2 * day)
        let retro = Save(title: "Retro format for PI planning", snippet: "Start, stop, continue, with one vote each. Try it with the team Tuesday.",
                         origin: "a note", kind: .note, createdAt: now - day / 2)
        let castIron = Save(title: "Cast iron care, the short version", snippet: "Dry it on the burner, thin coat of oil, wipe it back off.",
                            note: "Before the next cookout", origin: "Safari", kind: .link, urlString: "https://example.com/cast-iron", createdAt: now - 5 * day)
        castIron.imageData = Self.picture(top: 0x4A4A48, bottom: 0x1F1F1E, accent: 0xC77B4A)
        for s in [trail, pictureDay, teams, retro, castIron] {
            s.enrichedAt = now
            context.insert(s)
        }
        let away = Save(title: "Cleats size check", origin: "a note", kind: .note,
                        status: .away, returnDate: now + 2 * day, createdAt: now - 7 * day)
        let kept = Save(title: "Gutter cleaning quotes", origin: "via your Shoebox email", kind: .email, status: .kept, createdAt: now - 20 * day)
        for s in [away, kept] { s.enrichedAt = now; context.insert(s) }
        try? context.save()
    }

    /// Puts everything on Today away, for the "Today's clear" screen.
    static func clearToday(_ context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<Save>())) ?? []
        for s in all where s.status != .kept { s.status = .away; s.returnDate = Date() + 3 * 86_400 }
        try? context.save()
    }

    /// A soft landscape: sky, a far ridge and a near one, standing in for a page's photo.
    static func picture(top: UInt32, bottom: UInt32, accent: UInt32) -> Data? {
        let size = CGSize(width: 1200, height: 900)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            let colors = [UIColor(hex: top).cgColor, UIColor(hex: bottom).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            UIColor(hex: accent).withAlphaComponent(0.9).setFill()
            UIBezierPath(ovalIn: CGRect(x: 820, y: 140, width: 150, height: 150)).fill()
            let far = UIBezierPath()
            far.move(to: CGPoint(x: 0, y: 620))
            far.addCurve(to: CGPoint(x: 1200, y: 560), controlPoint1: CGPoint(x: 380, y: 420), controlPoint2: CGPoint(x: 760, y: 700))
            far.addLine(to: CGPoint(x: 1200, y: 900)); far.addLine(to: CGPoint(x: 0, y: 900)); far.close()
            UIColor(white: 0, alpha: 0.18).setFill(); far.fill()
            let near = UIBezierPath()
            near.move(to: CGPoint(x: 0, y: 760))
            near.addCurve(to: CGPoint(x: 1200, y: 720), controlPoint1: CGPoint(x: 500, y: 640), controlPoint2: CGPoint(x: 900, y: 820))
            near.addLine(to: CGPoint(x: 1200, y: 900)); near.addLine(to: CGPoint(x: 0, y: 900)); near.close()
            UIColor(white: 0, alpha: 0.3).setFill(); near.fill()
        }
        return img.jpegData(compressionQuality: 0.85)
    }
}
#endif
