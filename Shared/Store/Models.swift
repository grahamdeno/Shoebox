import Foundation
import SwiftData
import ShoeboxCore

// SwiftData records for docs/SPEC.md section 1. Enums are stored as their raw strings so a
// future value never breaks an old store. Every record has id, createdAt, updatedAt, deletedAt.

@Model
final class Save {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    var kindRaw: String
    var reason: String
    var reasonSourceRaw: String
    var title: String
    var text: String?
    var url: String?
    var author: String?
    var videoId: String?
    var imageURL: String?
    var summary: String
    var hook: String
    var points: [String]
    var extended: String
    var transcript: String
    var tags: [String]
    var minutes: Int?
    var intentRaw: String?
    var bookTitle: String?
    var bookAuthor: String?
    var focusX: Double?
    var focusY: Double?
    var alt: String
    var sourceRaw: String
    var statusRaw: String
    var passes: Int
    var laters: Int
    var nextMomentId: UUID?
    var doneAt: Date?
    var droppedAt: Date?
    var quietAt: Date?
    var loved: Bool
    var thoughtsJSON: String?
    var editedRaw: [String]
    var schoolJSON: String?
    var emailFrom: String?
    var emailFromName: String?
    var emailSubject: String?
    var emailReceivedAt: Date?
    var enrichedAt: Date?
    var enrichTries: Int
    var oldId: String?
    var suggested: Bool
    var modelPlannedAt: Date?
    /// SPEC 7.6: the day a dated post is for, whether it's a to-do or something that happens, and when it
    /// arrived in the email inbox (nil once kept or dropped).
    var dueDate: Date?
    var dueKindRaw: String?
    var inboxAt: Date?

    init(_ v: SaveValue) {
        id = v.id; createdAt = v.createdAt; updatedAt = v.updatedAt; deletedAt = v.deletedAt
        kindRaw = v.kind.rawValue; reason = v.reason; reasonSourceRaw = v.reasonSource.rawValue; title = v.title
        text = v.text; url = v.url; author = v.author; videoId = v.videoId; imageURL = v.imageURL
        summary = v.summary; hook = v.hook; points = v.points; extended = v.extended; transcript = v.transcript
        tags = v.tags; minutes = v.minutes; intentRaw = v.intent?.rawValue
        bookTitle = v.book?.title; bookAuthor = v.book?.author
        focusX = v.pictureFocus?.x; focusY = v.pictureFocus?.y; alt = v.alt
        sourceRaw = v.source.rawValue; statusRaw = v.status.rawValue; passes = v.passes; laters = v.laters
        nextMomentId = nil; doneAt = v.doneAt; droppedAt = v.droppedAt; quietAt = v.quietAt; loved = v.loved
        thoughtsJSON = (try? JSONEncoder().encode(v.thoughts)).flatMap { String(data: $0, encoding: .utf8) }
        editedRaw = v.edited.map(\.rawValue).sorted(); schoolJSON = v.schoolJSON
        emailFrom = v.email?.from; emailFromName = v.email?.fromName; emailSubject = v.email?.subject; emailReceivedAt = v.email?.receivedAt
        enrichedAt = nil; enrichTries = 0; oldId = v.oldId; suggested = false
    }

    var kind: SaveKind { get { SaveKind(rawValue: kindRaw) ?? .file } set { kindRaw = newValue.rawValue } }
    var status: SaveStatus { get { SaveStatus(rawValue: statusRaw) ?? .unplanned } set { statusRaw = newValue.rawValue } }
    var intent: Intent? { get { intentRaw.flatMap(Intent.init(rawValue:)) } set { intentRaw = newValue?.rawValue } }
    var source: SaveSource { SaveSource(rawValue: sourceRaw) ?? .share }
    var isBook: Bool { bookTitle != nil }
    var isSchool: Bool { schoolJSON != nil }
    var edited: Set<EditedField> { Set(editedRaw.compactMap(EditedField.init(rawValue:))) }
    var dueKind: DatedSteps.Kind { dueKindRaw == "todo" ? .todo : .happening }
    var inInbox: Bool { inboxAt != nil && deletedAt == nil && (status == .planned || status == .unplanned) }

    var thoughts: [Thought] {
        get { thoughtsJSON.flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode([Thought].self, from: $0) } ?? [] }
        set { thoughtsJSON = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } }
    }

    /// The words shown largest: your reason, or the title when you gave none.
    var headline: String { reason.isEmpty ? title : reason }

    var host: String? { url.flatMap(URL.init(string:))?.host()?.replacingOccurrences(of: "www.", with: "") }

    func touch(_ now: Date = .now) { updatedAt = now }
}

@Model
final class Attachment {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var saveId: UUID
    var roleRaw: String
    var fileName: String
    var mime: String
    var size: Int
    var sha256: String

    init(_ v: AttachmentValue) {
        id = v.id; createdAt = v.createdAt; updatedAt = v.createdAt; deletedAt = nil
        saveId = v.saveId; roleRaw = v.role.rawValue; fileName = v.fileName; mime = v.mime; size = v.size; sha256 = v.sha256
    }

    var role: AttachmentRole { AttachmentRole(rawValue: roleRaw) ?? .original }
    var fileURL: URL { AppGroup.url(forStored: fileName) }
}

@Model
final class Moment {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var saveId: UUID
    var start: Date
    var end: Date
    var surfaceRaw: String
    var placeRaw: String
    var anchorEventId: String?
    var ruleId: String
    var confidenceRaw: String
    var explanation: String
    var laterLabel: String
    var stateRaw: String
    var deliveredAt: Date?
    var answeredAt: Date?

    init(_ v: MomentValue, anchorEventId: String? = nil) {
        id = v.id; createdAt = v.createdAt; updatedAt = v.createdAt; deletedAt = nil
        saveId = v.saveId; start = v.start; end = v.end; surfaceRaw = v.surface.rawValue; placeRaw = v.place.rawValue
        self.anchorEventId = anchorEventId; ruleId = v.ruleId; confidenceRaw = v.confidence.rawValue
        explanation = v.explanation; laterLabel = v.laterLabel; stateRaw = v.state.rawValue
    }

    var surface: MomentSurface { MomentSurface(rawValue: surfaceRaw) ?? .notification }
    var place: MomentPlace { MomentPlace(rawValue: placeRaw) ?? .any }
    var confidence: MomentConfidence { MomentConfidence(rawValue: confidenceRaw) ?? .likely }
    var state: MomentState { get { MomentState(rawValue: stateRaw) ?? .scheduled } set { stateRaw = newValue.rawValue } }
}

@Model
final class MomentEvent {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var saveId: UUID
    var momentId: UUID?
    var typeRaw: String
    var at: Date
    var surface: String?
    var detail: String?

    init(saveId: UUID, momentId: UUID?, type: EventType, at: Date = .now, surface: String? = nil, detail: String? = nil) {
        id = UUID(); createdAt = at; updatedAt = at; deletedAt = nil
        self.saveId = saveId; self.momentId = momentId; typeRaw = type.rawValue; self.at = at
        self.surface = surface; self.detail = detail
    }

    var type: EventType? { EventType(rawValue: typeRaw) }
}

enum ShoeboxSchema {
    static let models: [any PersistentModel.Type] = [Save.self, Attachment.self, Moment.self, MomentEvent.self]
}
