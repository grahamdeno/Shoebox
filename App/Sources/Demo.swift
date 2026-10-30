import Foundation
import SwiftData
import ShoeboxCore

/// Sample saves for screenshots (`-demo`), taken from the spec's examples. Only ever in memory.
@MainActor
enum Demo {
    static var screen: String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-screen"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    static func seed(_ keeper: Keeper) {
        guard StoreBox.demo, keeper.allSaves().isEmpty else { return }
        Prefs.update { $0.onboarded = true; $0.importChecked = true; $0.palette = ProcessInfo.processInfo.arguments.contains("-gold") ? "gold" : "plum" }
        let items: [(SaveKind, String, String, String?, Int)] = [
            (.link, "Read before we plan next quarter", "How the best teams run planning", "https://hbr.org/planning", 11),
            (.photo, "Show the kids at dinner", "The comet over the pier", nil, 1),
            (.link, "Try the long cold ferment this weekend", "Overnight sourdough, step by step", "https://www.seriouseats.com/sourdough", 20),
            (.link, "Drive it next fall", "Blue Ridge Parkway: the best 50 miles", "https://www.blueridgeparkway.org", 8),
            (.video, "Watch with Kate this weekend", "The making of a lighthouse", "https://www.youtube.com/watch?v=dQw4w9WgXcQ", 95),
            (.note, "Gift idea for Sam's birthday", "Lego lighthouse set", nil, 1),
            (.link, "", "Why the shoebox works", "https://example.com/shoebox", 6),
        ]
        for (kind, reason, title, url, minutes) in items {
            var d = Detection.Draft(kind: kind, title: title)
            d.url = url
            let (s, _) = keeper.keep(d, reason: reason, reasonSource: .typed, source: .share)
            s.minutes = minutes
        }
        // Two school posts from email, waiting in the inbox: a to-do and something that happens.
        let cal = Calendar.current
        let posts: [(String, String, Int, String)] = [
            ("Sign up for student-led conferences", "Pick a 20-minute slot for Alex's conference. Sign up at https://www.signupgenius.com/go/lincoln-conferences before the week starts.", 9, "todo"),
            ("No school Monday: teacher workday", "School is closed Monday for a teacher workday. Classes pick up Tuesday at the usual time.", 3, "happening"),
        ]
        for (headline, body, days, kind) in posts {
            let (s, _) = keeper.keep(Detection.Draft(kind: .note, title: headline, text: body), reason: headline, reasonSource: .email, source: .school)
            s.schoolJSON = "{\"kind\":\"\(kind == "todo" ? "action" : "info")\",\"name\":\"Lincoln Middle\"}"
            s.dueDate = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: .now))
            s.dueKindRaw = kind
            s.inboxAt = .now
            s.emailFromName = "Lincoln Middle Weekly Updates"
            keeper.plan(s, events: [])
        }
        let quiet = keeper.keep(Detection.Draft(kind: .link, title: "A long piece on attention"), reason: "Someday", reasonSource: .typed, source: .share).0
        keeper.pass(quiet, events: []); keeper.pass(quiet, events: [])
        try? keeper.context.save()
    }
}
