import Foundation
import SwiftData

enum SaveStatus: String, Codable {
    case today   // on the table, shown until seen
    case away    // put away until returnDate
    case kept    // done, in the archive
}

enum SaveKind: String, Codable {
    case link, note, photo
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
    var snippet: String = ""
    /// The user's own words: why they kept it. Shown as a peach highlight.
    var note: String = ""
    var source: String = ""
    var kindRaw: String = SaveKind.note.rawValue
    var urlString: String?
    var imageData: Data?

    var statusRaw: String = SaveStatus.today.rawValue
    var returnDate: Date?
    /// The day it was last shown. Once seen, it is gone until tomorrow.
    var seenOn: Date?
    /// For dated saves (school emails, events): comes back 5 days before,
    /// 1 day before and on the day.
    var eventDate: Date?

    init(
        title: String,
        snippet: String = "",
        note: String = "",
        source: String = "",
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
        self.note = note
        self.source = source
        self.kindRaw = kind.rawValue
        self.urlString = urlString
        self.imageData = imageData
        self.statusRaw = status.rawValue
        self.returnDate = returnDate
        self.eventDate = eventDate
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var status: SaveStatus {
        get { SaveStatus(rawValue: statusRaw) ?? .today }
        set { statusRaw = newValue.rawValue }
    }

    var kind: SaveKind {
        get { SaveKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }
}
