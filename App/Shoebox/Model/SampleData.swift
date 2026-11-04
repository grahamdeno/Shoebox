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
        let cal = Calendar.current
        func inDays(_ n: Int, hour: Int) -> Date? {
            cal.date(bySettingHour: hour, minute: 0, second: 0, of: cal.date(byAdding: .day, value: n, to: now) ?? now)
        }

        let trail = Save(title: "A trail worth the drive", snippet: "Coastal loop, 4 miles, about 2 hours away. A lookout halfway and a beach at the end.",
                         body: "A 4 mile coastal loop with a lookout halfway. Parking fills by 9 on weekends, so go early. The trailhead parking details are at https://example.com/trail/parking.",
                         note: "Take the kids in the fall", origin: "Safari", kind: .link,
                         urlString: "https://example.com/trail", createdAt: now - 14 * day)
        trail.imageData = Self.photo("trail") ?? Self.picture(top: 0x6E8392, bottom: 0x3F5566, accent: 0xE8D9B5)
        let bread = Save(title: "Sourdough, the slow way", snippet: "A starter, an overnight rise and a very hot oven.",
                         body: "Feed the starter in the morning, mix in the evening, shape and rest overnight in the fridge, then bake at 475 in a covered pot.",
                         note: "Try this weekend", origin: "Safari", kind: .link,
                         urlString: "https://example.com/sourdough", createdAt: now - 9 * day)
        bread.imageData = Self.photo("bread") ?? Self.picture(top: 0x9C826B, bottom: 0x5E4B3C, accent: 0xF2E3CF)
        let pictureDay = Save(title: "School picture day", snippet: "Order forms are due the day before. Retakes are next month.",
                              body: "School picture day. Order forms are due the day before. Retakes are next month.",
                              origin: "via the school newsletter email", kind: .email,
                              eventDate: inDays(3, hour: 8), createdAt: now - 2 * day)
        let tryouts = Save(title: "Soccer tryouts", snippet: "Bring cleats, shin guards and water. Field 2 behind the gym.",
                           body: "Soccer tryouts are on Field 2 behind the gym. Bring cleats, shin guards and water.",
                           origin: "via the team email", kind: .email,
                           eventDate: inDays(5, hour: 16), createdAt: now - day)
        tryouts.eventHasTime = true
        let dinner = Save(title: "Birthday dinner", snippet: "Table for six on the patio at 7.",
                          note: "Book the patio table", origin: "a note", kind: .note,
                          eventDate: inDays(9, hour: 19), createdAt: now - day / 2)
        dinner.eventHasTime = true
        let castIron = Save(title: "Cast iron care, the short version", snippet: "Dry it on the burner, thin coat of oil, wipe it back off.",
                            note: "Before the next cookout", origin: "Safari", kind: .link, urlString: "https://example.com/cast-iron", createdAt: now - 5 * day)
        castIron.imageData = Self.photo("castiron") ?? Self.picture(top: 0x4A4A48, bottom: 0x1F1F1E, accent: 0xC77B4A)
        for s in [trail, pictureDay, bread, tryouts, dinner, castIron] {
            s.enrichedAt = now
            s.stockTriedAt = now
            context.insert(s)
        }
        let away = Save(title: "Cleats size check", origin: "a note", kind: .note,
                        status: .away, returnDate: now + 2 * day, createdAt: now - 7 * day)
        let kept = Save(title: "Gutter cleaning quotes", origin: "via your Shoebox email", kind: .email, status: .kept, createdAt: now - 20 * day)
        for s in [away, kept] { s.enrichedAt = now; s.stockTriedAt = now; context.insert(s) }
        try? context.save()
    }

    /// Puts everything on Today away, for the "Today's clear" screen.
    static func clearToday(_ context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<Save>())) ?? []
        for s in all where s.status != .kept { s.status = .away; s.returnDate = Date() + 3 * 86_400 }
        try? context.save()
    }

    /// A real photo for the App Store screenshots, when the screenshot job has put one in the app's Documents folder
    /// as demo-photos/<name>.jpg (fetched from Pixabay on the build machine). Nil otherwise: the drawn stand-in is used.
    static func photo(_ name: String) -> Data? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let data = try? Data(contentsOf: docs.appending(path: "demo-photos/\(name).jpg")) else { return nil }
        return Relay.thumbnail(data)
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
