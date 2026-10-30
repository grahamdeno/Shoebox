import Foundation
import SwiftData

#if DEBUG
/// Five saves for trying the app in a debug build. Never ships in a release build.
enum SampleData {
    static func seedIfEmpty(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Save>())) ?? 0
        guard count == 0 else { return }
        let now = Date()
        let day: TimeInterval = 86_400
        let event = Calendar.current.date(byAdding: .day, value: 12, to: now)
        let samples: [Save] = [
            Save(title: "A trail worth the drive", snippet: "Coastal loop, 4 miles, about 2 hours away.",
                 note: "Take the kids in the fall", source: "You, 2 weeks ago, from Safari",
                 kind: .link, urlString: "https://example.com/trail", createdAt: now - 14 * day),
            Save(title: "Picture day", snippet: "Order forms are due the week before. Retakes are in December.",
                 source: "You, via the school newsletter email", kind: .note,
                 status: .away, returnDate: now - 60, eventDate: event, createdAt: now - 2 * day),
            Save(title: "Why small teams ship faster", snippet: "Three habits that cut handoffs in half. 6 min read.",
                 note: "Read before Monday", source: "You, 9 days ago, from Safari",
                 kind: .link, urlString: "https://example.com/teams", createdAt: now - 9 * day),
            Save(title: "Retro format for PI planning", snippet: "Start, stop, continue, with one vote each. Try it with the team Tuesday.",
                 source: "You, last night, a note", kind: .note, createdAt: now - day / 2),
            Save(title: "Cast iron care, the short version", snippet: "Dry it on the burner, thin coat of oil, wipe it back off.",
                 note: "Before the next cookout", source: "You, a month ago", kind: .note, createdAt: now - 30 * day),
        ]
        for sample in samples { context.insert(sample) }
        let away = Save(title: "Cleats size check", source: "You, last week", kind: .note,
                        status: .away, returnDate: now + 2 * day, createdAt: now - 7 * day)
        context.insert(away)
        try? context.save()
    }
}
#endif
