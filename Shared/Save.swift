import Foundation
import SwiftData

enum SaveStatus: String, Codable {
    case today   // on the table, shown until seen
    case away    // put away until returnDate
    case kept    // done, in the archive
}

enum SaveKind: String, Codable {
    case link, note, photo, quote, video, file, email
}

/// A save. Every property has a default and every record has an id,
/// timestamps and a soft-delete marker, so sync can be added later
/// without a migration.
@Model
final class Save {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    var title: String = ""
    /// One or two lines under the headline.
    var snippet: String = ""
    /// The full text shown when the post is opened (an email, a note, the page's text).
    var body: String = ""
    /// The user's own words: why they kept it. Shown as a Nectarine-tint highlight.
    var note: String = ""
    /// Legacy display line. New saves leave it empty and the line is built from `origin` and `createdAt`.
    var source: String = ""
    /// Where it came from, in words: "Safari", "your Shoebox email", "a note", "Shoebox 1".
    var origin: String = ""
    var kindRaw: String = SaveKind.note.rawValue
    var urlString: String?
    /// The page's picture on the web. The picture itself is kept in `imageData` once fetched.
    var imageURL: String?
    @Attribute(.externalStorage) var imageData: Data?

    var statusRaw: String = SaveStatus.today.rawValue
    var returnDate: Date?
    /// The day it was last shown. Once seen, it is gone until tomorrow.
    var seenOn: Date?
    /// For dated saves (school emails, events): comes back 5 days before,
    /// 1 day before and on the day.
    var eventDate: Date?
    /// True when the event date carries a time of day ("4:00 PM"), not just a day.
    var eventHasTime: Bool = false
    /// Other dates named in the words (a deadline, a second day), as epoch seconds, comma separated.
    var otherDatesRaw: String = ""

    /// Where the picture came from: "page" (the link's own), "photo" (yours) or "stock" (found for you).
    var imageSource: String?
    /// When a stock picture was last looked for, so a miss is retried tomorrow and not every launch.
    var stockTriedAt: Date?

    /// Link preview: when it was fetched, and how many times it failed.
    var enrichedAt: Date?
    var enrichTries: Int = 0

    /// Email details, so the same message is kept once.
    var emailFrom: String?
    var emailSubject: String?
    var emailReceivedAt: Date?

    /// The id this save had in Shoebox 1, so importing twice adds nothing.
    var oldId: String?

    init(
        title: String,
        snippet: String = "",
        body: String = "",
        note: String = "",
        source: String = "",
        origin: String = "",
        kind: SaveKind = .note,
        urlString: String? = nil,
        imageData: Data? = nil,
        status: SaveStatus = .today,
        returnDate: Date? = nil,
        eventDate: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.title = title
        self.snippet = snippet
        self.body = body
        self.note = note
        self.source = source
        self.origin = origin
        self.kindRaw = kind.rawValue
        self.urlString = urlString
        self.imageData = imageData
        self.statusRaw = status.rawValue
        self.returnDate = returnDate
        self.eventDate = eventDate
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var otherDates: [Date] {
        get { otherDatesRaw.split(separator: ",").compactMap { Double($0) }.map { Date(timeIntervalSince1970: $0) } }
        set { otherDatesRaw = newValue.map { String(Int($0.timeIntervalSince1970)) }.joined(separator: ",") }
    }

    var status: SaveStatus {
        get { SaveStatus(rawValue: statusRaw) ?? .today }
        set { statusRaw = newValue.rawValue }
    }

    var kind: SaveKind {
        get { SaveKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }

    var url: URL? { urlString.flatMap(URL.init(string:)) }

    var host: String? { url?.host()?.replacingOccurrences(of: "www.", with: "") }

    /// Shown largest. Never empty.
    var headline: String {
        if !title.isEmpty { return title }
        if let host { return host }
        return note.isEmpty ? "Untitled" : note
    }

    /// "You, 2 weeks ago, from Safari"
    func byline(now: Date = Date()) -> String {
        if !source.isEmpty && origin.isEmpty { return source }
        let when = Self.relative(createdAt, now: now)
        var parts = ["You", when]
        if !origin.isEmpty { parts.append(origin.hasPrefix("via ") ? origin : "from \(origin)") }
        else if let host { parts.append("from \(host)") }
        return parts.joined(separator: ", ")
    }

    static func relative(_ date: Date, now: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        case 2..<7: return "\(days) days ago"
        case 7..<14: return "last week"
        case 14..<31: return "\(days / 7) weeks ago"
        case 31..<62: return "a month ago"
        case 62..<365: return "\(days / 30) months ago"
        default: return days < 730 ? "a year ago" : "\(days / 365) years ago"
        }
    }
}
