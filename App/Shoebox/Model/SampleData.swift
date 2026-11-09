import Foundation
import SwiftData
import UIKit

#if DEBUG
/// Saves for the simulator and screenshots (`-demo YES`). In memory only; never ships in a release build.
enum SampleData {
    static func seed(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Save>())) ?? 0
        guard count == 0 else { return }
        let now = Clock.now
        let day: TimeInterval = 86_400

        let trail = Save(title: "A trail worth the drive", snippet: "Coastal loop, 4 miles, about 2 hours away. A lookout halfway and a beach at the end.",
                         body: "A 4 mile coastal loop with a lookout halfway. Parking fills by 9 on weekends, so go early. The trailhead parking details are at https://example.com/trail/parking.",
                         note: "Take the kids in the fall", origin: "Safari", kind: .link,
                         urlString: "https://example.com/trail", createdAt: now - 14 * day)
        trail.imageData = Self.photo("trail") ?? Self.picture(top: 0x6E8392, bottom: 0x3F5566, accent: 0xE8D9B5)
        let teams = Save(title: "Why small teams ship faster", snippet: "Three habits that cut handoffs in half.",
                         body: "Small teams ship faster because they hand off less. Three habits help: one owner per outcome, decisions written down the day they're made, and demos every week.",
                         note: "Read before Monday", origin: "Safari", kind: .link,
                         urlString: "https://example.com/teams", createdAt: now - 9 * day)
        teams.imageData = Self.photo("teams") ?? Self.picture(top: 0x9C826B, bottom: 0x5E4B3C, accent: 0xF2E3CF)
        let retro = Save(title: "Retro format for PI planning", snippet: "Start, stop, continue, with one vote each. Try it with the team Tuesday.",
                         origin: "a note", kind: .note, createdAt: now - day / 2)
        let castIron = Save(title: "Cast iron care, the short version", snippet: "Dry it on the burner, thin coat of oil, wipe it back off.",
                            note: "Before the next cookout", origin: "Safari", kind: .link, urlString: "https://example.com/cast-iron", createdAt: now - 5 * day)
        castIron.imageData = Self.photo("cookout") ?? Self.picture(top: 0x4A4A48, bottom: 0x1F1F1E, accent: 0xC77B4A)
        // The post the screenshots lead with: forwarded by email, dated, with a reason, back on Today now.
        let saturday = Self.nextSaturday(after: now, hour: 17)
        let concert = Save(title: "Fall band concert",
                           snippet: "Saturday at 5 in the school gym. Band students arrive by 4:30 in black and white.",
                           body: "The fall band concert is Saturday at 5 PM in the school gym. Band students arrive by 4:30, dressed in black and white. Families are welcome; doors open at 4:45.",
                           note: "Bring the good camera", origin: "via your Shoebox email", kind: .email,
                           status: .away, returnDate: now - 3_600, eventDate: saturday, createdAt: now - 2 * day)
        concert.eventHasTime = true
        concert.emailFrom = "office@example.org"
        concert.emailSubject = "Fall band concert"
        concert.emailReceivedAt = now - 2 * day
        concert.imageData = Self.photo("concert") ?? Self.picture(top: 0x7A4E3A, bottom: 0x2E1C24, accent: 0xF9C93A)
        // "dates" opens on the newsletter's first date post: everything older steps aside until tomorrow.
        if UserDefaults.standard.string(forKey: "screen") == "dates" {
            for s in [concert, trail, teams, retro, castIron] { s.status = .away; s.returnDate = now + 3 * day }
        }
        for s in [concert, trail, teams, retro, castIron] {
            s.enrichedAt = now
            context.insert(s)
        }
        for s in Self.newsletter(now: now) { s.enrichedAt = now; context.insert(s) }
        let away = Save(title: "Cleats size check", origin: "a note", kind: .note,
                        status: .away, returnDate: now + 2 * day, createdAt: now - 7 * day)
        let kept = Save(title: "Gutter cleaning quotes", origin: "via your Shoebox email", kind: .email, status: .kept, createdAt: now - 20 * day)
        for s in [away, kept] { s.enrichedAt = now; context.insert(s) }
        // The UX audit's odd data (`-dataset heavy` or `nophotos`), to find what breaks at the edges.
        switch UserDefaults.standard.string(forKey: "dataset") ?? "" {
        case "heavy": for s in Self.heavy(now: now) { context.insert(s) }
        case "nophotos": for s in [trail, teams, castIron, concert] { s.imageData = nil; s.imageSource = nil }
        default: break
        }
        try? context.save()
    }

    /// 500 more posts, the kind a year of keeping makes, and the kind that breaks layouts: very long titles, one long
    /// word, other languages and scripts, emoji, a bare link, words with no title. A quarter put away, a fifth away for
    /// later, some dated. No pictures, so the run measures the list and the rules, not image decoding.
    static func heavy(now: Date) -> [Save] {
        let day: TimeInterval = 86_400
        let odd = [
            "A very long title that keeps going well past where any sensible person would stop writing, because someone pasted the whole first paragraph of an article into the title by mistake and never fixed it",
            "Donaudampfschifffahrtsgesellschaftskapitänsmützenreinigung",
            "Receta de pan de masa madre para principiantes, paso a paso",
            "週末の山歩きの持ち物リスト",
            "قائمة الكتب التي يجب قراءتها هذا الصيف",
            "Пирог с капустой, бабушкин рецепт",
            "🎸🎶 New strings, tune down a half step 🎶🎸",
            "https://example.com/a/very/long/link/with/many/parts/and?query=string&that=never&ends=true",
            "",
            "Q4",
        ]
        let topics = ["Recipe", "Trail", "Article", "Gift idea", "School form", "Book", "Podcast", "Fix the", "Call about", "Look into"]
        var made: [Save] = []
        for i in 0..<500 {
            let title = i < odd.count * 3 ? odd[i % odd.count] : "\(topics[i % topics.count]) \(i)"
            let words = i % 7 == 0 ? String(repeating: "Words that go on for a while. ", count: 40) : "Saved for later, number \(i)."
            let created = now - Double(i % 400) * day - Double(i) * 60
            let s = Save(title: title, snippet: String(words.prefix(240)), body: words,
                         note: i % 5 == 0 ? "Before the weekend" : "", origin: i % 3 == 0 ? "Safari" : "a note",
                         kind: i % 3 == 0 ? .link : .note, urlString: i % 3 == 0 ? "https://example.com/\(i)" : nil,
                         createdAt: created)
            switch i % 20 {
            case 0..<5: s.status = .kept
            case 5..<9: s.status = .away; s.returnDate = now + Double(1 + i % 30) * day
            default: break
            }
            if i % 25 == 3 { s.eventDate = now + Double(2 + i % 60) * day }
            s.enrichedAt = now
            made.append(s)
        }
        return made
    }

    /// Six dates from one fictional school newsletter, made the way `Inbox` makes them: one post per date that is about
    /// "Sam, 7th grade, band", the day first, "from Maple Grove newsletter" in the byline, no picture, on Today when it arrives.
    static func newsletter(now: Date) -> [Save] {
        let cal = Calendar.current
        let received = now - 600
        let dayText = DateFormatter(); dayText.dateFormat = "EEEE, MMM d"
        let timeText = DateFormatter(); timeText.dateFormat = "h:mm a"
        // (days out, title, hour or nil, the rest of the first line, more words)
        let dates: [(Int, String, Int?, String, String)] = [
            (9, "Picture day", nil, "Order forms are due the week before.", "Retakes are in December."),
            (13, "Early release day", nil, "Students go home at 12:30.", "Buses run early. After-school clubs are off."),
            (16, "Field trip forms due", nil, "7th grade, signed and back in the office.", "Forms are in the Friday folder."),
            (20, "Band fundraiser pickup", 16, "Gym lobby. Bring the pickup slip.", "Orders not picked up by 5 PM go home Monday."),
            (27, "No school: teacher workday", nil, "No classes for students.", "Regular schedule resumes the next day."),
            (34, "Winter band concert", 18, "Auditorium. 7th and 8th grade band.", "Arrive by 5:45 in black and white."),
        ]
        var made: [Save] = []
        for (i, d) in dates.enumerated() {
            var day = cal.startOfDay(for: cal.date(byAdding: .day, value: d.0, to: now) ?? now)
            while cal.isDateInWeekend(day) { day = cal.date(byAdding: .day, value: 1, to: day) ?? day }
            let at = d.2.flatMap { cal.date(bySettingHour: $0, minute: d.2 == 18 ? 30 : 0, second: 0, of: day) } ?? day
            var first = dayText.string(from: day)
            if d.2 != nil { first += " · " + timeText.string(from: at) }
            let words = "\(first) · \(d.3) \(d.4)"
            let s = Save(title: d.1, snippet: words, body: words,
                         origin: "Maple Grove newsletter", kind: .email, createdAt: received + Double(i) * 60)
            s.eventDate = at
            s.eventHasTime = d.2 != nil
            s.emailFrom = "office@example.org"
            s.emailSubject = "Maple Grove Middle School: November news"
            s.emailReceivedAt = received
            made.append(s)
        }
        return made
    }

    /// Where the time replay keeps its store: in Documents, never the real store. `-replayReset YES` (day 0) starts it
    /// again from nothing, with the day's pick and the put-away log cleared.
    static func replayStore() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "AuditReplay")
        if UserDefaults.standard.bool(forKey: "replayReset") {
            try? FileManager.default.removeItem(at: dir)
            Prefs.pickIds = []
            Prefs.pickDay = nil
            AppGroup.defaults.removeObject(forKey: "putAwayAt")
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "replay.store")
    }

    /// Puts everything on Today away, for the "Today's clear" screen.
    static func clearToday(_ context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<Save>())) ?? []
        for s in all where s.status != .kept { s.status = .away; s.returnDate = Clock.now + 3 * 86_400 }
        try? context.save()
    }

    /// A real photo for the screenshots, if one was copied into the simulator (Scripts/screens.sh copies
    /// Scripts/demo-photos/<name>.jpg into Documents/DemoPhotos). Nil otherwise, and the drawn one is used.
    static func photo(_ name: String) -> Data? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let data = try? Data(contentsOf: docs.appending(path: "DemoPhotos/\(name).jpg")) else { return nil }
        return Relay.thumbnail(data, maxWidth: 1600) ?? data
    }

    /// The next Saturday at least two days away, at the given hour.
    static func nextSaturday(after now: Date, hour: Int) -> Date {
        let cal = Calendar.current
        var day = cal.startOfDay(for: now)
        for _ in 0..<9 {
            day = cal.date(byAdding: .day, value: 1, to: day) ?? day
            if cal.component(.weekday, from: day) == 7, day.timeIntervalSince(now) > 2 * 86_400 { break }
        }
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
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
