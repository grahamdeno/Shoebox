import Foundation
import ShoeboxCore
import SwiftData

/// Turns what you keep (pasted text, a shared page, a photo) into saves.
/// Several links pasted together become several saves.
enum Capture {
    /// Saves for text: a link, several links, a quote or a note.
    static func saves(fromText raw: String, note: String, origin: String, now: Date = Date()) -> [Save] {
        let drafts = Detection.drafts(fromText: raw)
        return drafts.map { make($0, note: note, origin: origin, now: now) }
    }

    static func save(fromURL url: URL, title: String?, note: String, origin: String, now: Date = Date()) -> Save {
        make(Detection.draft(fromURL: url, title: title), note: note, origin: origin, now: now)
    }

    static func save(photo data: Data, note: String, origin: String, now: Date = Date()) -> Save {
        let s = Save(title: "A photo", note: String(note.prefix(140)), origin: origin, kind: .photo, createdAt: now)
        s.imageData = Relay.thumbnail(data, maxWidth: 1600) ?? data
        s.enrichedAt = now
        place(s, note: note, now: now)
        return s
    }

    private static func make(_ d: Detection.Draft, note: String, origin: String, now: Date) -> Save {
        let kind: SaveKind
        switch d.kind {
        case .link: kind = .link
        case .quote: kind = .quote
        case .video: kind = .video
        case .photo: kind = .photo
        case .pdf, .file: kind = .file
        case .note: kind = .note
        }
        var title = d.title
        var snippet = ""
        var body = ""
        if kind == .note, let text = d.text {
            let lines = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            title = String((lines.first ?? "").prefix(90))
            body = text
            if lines.count > 1 { snippet = String(lines[1].prefix(200)) }
        } else if kind == .quote, let text = d.text {
            title = text
            if let a = d.author { snippet = a }
        }
        let s = Save(title: title, snippet: snippet, body: body, note: String(note.prefix(140)), origin: origin, kind: kind,
                     urlString: d.url, createdAt: now)
        s.imageURL = d.imageURL
        if s.url == nil { s.enrichedAt = now }
        place(s, note: note, now: now)
        return s
    }

    /// A new save is put away until your reason says, or tomorrow morning. A save whose words name a date
    /// still ahead is dated: it comes back 5 days before, 1 day before and on the day, unless your reason names a time.
    static func place(_ s: Save, note: String, now: Date) {
        let planner = LaterPlanner()
        DateReader.apply(to: s)
        if let event = s.eventDate, planner.match(words: note, now: now) == nil {
            if let first = SaveActions().reminders(for: event).first(where: { $0 > now }) {
                s.status = .away
                s.returnDate = first
            } else {
                s.status = .today        // the day is here
                s.returnDate = nil
            }
            return
        }
        s.status = .away
        s.returnDate = planner.firstReturn(note: note, now: now)
    }

    /// A page's own text arrived after the save was made: read its dates now. A save that is waiting
    /// comes back before the date; one that is on screen stays where it is.
    static func adoptDates(_ s: Save, now: Date) {
        guard s.deletedAt == nil, s.status != .kept, DateReader.apply(to: s), let event = s.eventDate else { return }
        guard s.status == .away, let due = s.returnDate, due > now,
              LaterPlanner().match(words: s.note, now: now) == nil,
              let first = SaveActions().reminders(for: event).first(where: { $0 > now }), first < due else { return }
        s.returnDate = first
        s.updatedAt = now
    }

    /// Same link already kept and not let go: don't keep it twice.
    static func isDuplicate(_ s: Save, in context: ModelContext) -> Bool {
        guard let link = s.urlString else { return false }
        let d = FetchDescriptor<Save>(predicate: #Predicate { $0.urlString == link && $0.deletedAt == nil })
        return ((try? context.fetchCount(d)) ?? 0) > 0
    }
}
