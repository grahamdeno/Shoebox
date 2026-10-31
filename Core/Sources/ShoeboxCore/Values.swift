import Foundation

// Plain value types for the records in docs/SPEC.md section 1.
// The app persists them with SwiftData; the importer and the planner work on these.

public enum SaveKind: String, Codable, CaseIterable, Sendable { case link, note, quote, photo, pdf, file, video }

public enum SaveStatus: String, Codable, CaseIterable, Sendable { case planned, unplanned, quiet, done, dropped }

public enum ReasonSource: String, Codable, Sendable { case typed, spoken, shareComment, email, imported, none }

public enum SaveSource: String, Codable, Sendable { case share, actionButton, siri, paste, email, screenshot, school, `import` }

public enum Intent: String, Codable, Sendable { case read, watch, listen, reference, idea, task }

public enum EditedField: String, Codable, Sendable { case title, tags, reason }

public enum AttachmentRole: String, Codable, Sendable { case original, thumbnail, picture }

public enum MomentSurface: String, Codable, Sendable { case issue, notification, liveActivity }

public enum MomentPlace: String, Codable, Sendable { case any, homeEvening, work, weekend }

public enum MomentConfidence: String, Codable, Sendable { case sure, likely, guess }

public enum MomentState: String, Codable, Sendable { case scheduled, delivered, answered, passed, cancelled }

public enum EventType: String, Codable, Sendable {
    case saved, planned, delivered, opened, done, later, dropped, passed, quiet, broughtBack, restored, edited
}

public struct Book: Codable, Equatable, Sendable {
    public var title: String; public var author: String
    public init(title: String, author: String) { self.title = title; self.author = author }
}
public struct PictureFocus: Codable, Equatable, Sendable {
    public var x: Double; public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}
public struct Thought: Codable, Equatable, Sendable {
    public var at: Date; public var text: String
    public init(at: Date, text: String) { self.at = at; self.text = text }
}
public struct EmailInfo: Codable, Equatable, Sendable {
    public var from: String?; public var fromName: String?; public var subject: String?; public var receivedAt: Date?
    public init(from: String?, fromName: String?, subject: String?, receivedAt: Date?) {
        self.from = from; self.fromName = fromName; self.subject = subject; self.receivedAt = receivedAt
    }
}

public struct SaveValue: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public var kind: SaveKind
    public var reason: String
    public var reasonSource: ReasonSource
    public var title: String
    public var text: String?
    public var url: String?
    public var author: String?
    public var videoId: String?
    public var imageURL: String?
    public var summary: String
    public var hook: String
    public var points: [String]
    public var extended: String
    public var transcript: String
    public var tags: [String]
    public var minutes: Int?
    public var intent: Intent?
    public var book: Book?
    public var pictureFocus: PictureFocus?
    public var alt: String
    public var source: SaveSource
    public var status: SaveStatus
    public var passes: Int
    public var laters: Int
    public var doneAt: Date?
    public var droppedAt: Date?
    public var quietAt: Date?
    public var loved: Bool
    public var thoughts: [Thought]
    public var edited: Set<EditedField>
    /// School post details as JSON; the typed form arrives with the school work in phase 5.
    public var schoolJSON: String?
    public var email: EmailInfo?
    public var oldId: String?

    public init(id: UUID = UUID(), now: Date = Date(), kind: SaveKind, title: String = "", reason: String = "",
                reasonSource: ReasonSource = .none, source: SaveSource = .share, status: SaveStatus = .unplanned) {
        self.id = id; createdAt = now; updatedAt = now; deletedAt = nil
        self.kind = kind; self.reason = reason; self.reasonSource = reasonSource; self.title = title
        text = nil; url = nil; author = nil; videoId = nil; imageURL = nil
        summary = ""; hook = ""; points = []; extended = ""; transcript = ""; tags = []
        minutes = nil; intent = nil; book = nil; pictureFocus = nil; alt = ""
        self.source = source; self.status = status; passes = 0; laters = 0
        doneAt = nil; droppedAt = nil; quietAt = nil; loved = false; thoughts = []; edited = []
        schoolJSON = nil; email = nil; oldId = nil
    }
}

public struct AttachmentValue: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var saveId: UUID
    public var role: AttachmentRole
    public var fileName: String   // Files/<id>.<ext>
    public var mime: String
    public var size: Int
    public var sha256: String
    public var createdAt: Date

    public init(id: UUID, saveId: UUID, role: AttachmentRole, fileName: String, mime: String, size: Int, sha256: String, createdAt: Date) {
        self.id = id; self.saveId = saveId; self.role = role; self.fileName = fileName; self.mime = mime
        self.size = size; self.sha256 = sha256; self.createdAt = createdAt
    }
}

public struct MomentValue: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var saveId: UUID
    public var start: Date
    public var end: Date
    public var surface: MomentSurface
    public var place: MomentPlace
    public var ruleId: String
    public var confidence: MomentConfidence
    public var explanation: String
    public var laterLabel: String
    public var state: MomentState
    public var createdAt: Date

    public init(id: UUID, saveId: UUID, start: Date, end: Date, surface: MomentSurface, place: MomentPlace, ruleId: String,
                confidence: MomentConfidence, explanation: String, laterLabel: String, state: MomentState, createdAt: Date) {
        self.id = id; self.saveId = saveId; self.start = start; self.end = end; self.surface = surface; self.place = place
        self.ruleId = ruleId; self.confidence = confidence; self.explanation = explanation; self.laterLabel = laterLabel
        self.state = state; self.createdAt = createdAt
    }
}

public struct EventValue: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var saveId: UUID
    public var momentId: UUID?
    public var type: EventType
    public var at: Date
    public var detail: String?

    public init(id: UUID, saveId: UUID, momentId: UUID?, type: EventType, at: Date, detail: String?) {
        self.id = id; self.saveId = saveId; self.momentId = momentId; self.type = type; self.at = at; self.detail = detail
    }
}
