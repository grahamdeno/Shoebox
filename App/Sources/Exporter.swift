import Foundation
import ShoeboxCore

/// Shoebox's own backup (SPEC 1.7): `{app:"shoebox", format:3, ...}`. Files ride along as base64 in the
/// same JSON. [Check] The spec suggests a .shoebox zip; one JSON file is simpler to restore and needs no library.
/// The email-in key and AI sign-up are left out unless you ask for them.
@MainActor
enum Exporter {
    struct FileEntry: Codable { var attachment: AttachmentValue; var data: String }
    struct Backup: Codable {
        var app = "shoebox"
        var format = 3
        var exported: Date
        var saves: [SaveValue]
        var moments: [MomentValue]
        var events: [EventValue]
        var files: [FileEntry]
        var settings: Prefs
    }

    static func export(_ keeper: Keeper, includeAccount: Bool) throws -> URL {
        let saves = keeper.allSaves()
        var files: [FileEntry] = []
        var moments: [MomentValue] = []
        var events: [EventValue] = []
        for s in saves {
            for a in keeper.attachments(for: s) {
                guard let d = try? Data(contentsOf: a.fileURL) else { continue }
                files.append(FileEntry(attachment: AttachmentValue(id: a.id, saveId: a.saveId, role: a.role, fileName: a.fileName, mime: a.mime,
                                                                   size: a.size, sha256: a.sha256, createdAt: a.createdAt), data: d.base64EncodedString()))
            }
            if let m = keeper.nextMoment(for: s) {
                moments.append(MomentValue(id: m.id, saveId: m.saveId, start: m.start, end: m.end, surface: m.surface, place: m.place, ruleId: m.ruleId,
                                           confidence: m.confidence, explanation: m.explanation, laterLabel: m.laterLabel, state: m.state, createdAt: m.createdAt))
            }
            for e in keeper.events(for: s) {
                if let t = e.type { events.append(EventValue(id: e.id, saveId: e.saveId, momentId: e.momentId, type: t, at: e.at, detail: e.detail)) }
            }
        }
        var prefs = Prefs.load()
        if !includeAccount { prefs.inboxKey = nil; prefs.aiToken = nil; prefs.aiDevice = nil; prefs.aiAttested = nil }
        let b = Backup(exported: .now, saves: saves.map(\.value), moments: moments, events: events, files: files, settings: prefs)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        let day = Date.now.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appending(path: "Shoebox \(day).json")
        try enc.encode(b).write(to: url, options: .atomic)
        return url
    }

    static func read(_ data: Data) throws -> Backup {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let b = try dec.decode(Backup.self, from: data)
        guard b.app == "shoebox", b.format == 3 else { throw BackupImporter.Failure.notABackup }
        return b
    }

    /// Restores saves that aren't already here (by id). Nothing here is overwritten.
    static func restore(_ b: Backup, keeper: Keeper) throws -> ImportService.Outcome {
        let have = Set(keeper.allSaves(includeDeleted: true).map(\.id))
        let ctx = keeper.context
        var added = 0
        let fresh = b.saves.filter { !have.contains($0.id) }
        let ids = Set(fresh.map(\.id))
        for v in fresh { ctx.insert(Save(v)); added += 1 }
        for f in b.files where ids.contains(f.attachment.saveId) {
            guard let d = Data(base64Encoded: f.data) else { continue }
            try? d.write(to: AppGroup.url(forStored: f.attachment.fileName), options: .atomic)
            ctx.insert(Attachment(f.attachment))
        }
        for m in b.moments where ids.contains(m.saveId) {
            ctx.insert(Moment(m))
            keeper.save(id: m.saveId)?.nextMomentId = m.id
        }
        for e in b.events where ids.contains(e.saveId) {
            ctx.insert(MomentEvent(saveId: e.saveId, momentId: e.momentId, type: e.type, at: e.at, surface: "import", detail: e.detail))
        }
        try ctx.save()
        return .init(text: added == 0 ? "Everything in that backup is already here." : "\(added) \(added == 1 ? "save" : "saves") came back.", count: added)
    }
}

extension Save {
    var value: SaveValue {
        var v = SaveValue(id: id, now: createdAt, kind: kind, title: title, reason: reason,
                          reasonSource: ReasonSource(rawValue: reasonSourceRaw) ?? .none, source: source, status: status)
        v.updatedAt = updatedAt; v.deletedAt = deletedAt
        v.text = text; v.url = url; v.author = author; v.videoId = videoId; v.imageURL = imageURL
        v.summary = summary; v.hook = hook; v.points = points; v.extended = extended; v.transcript = transcript; v.tags = tags
        v.minutes = minutes; v.intent = intent
        if let t = bookTitle { v.book = Book(title: t, author: bookAuthor ?? "") }
        if let x = focusX, let y = focusY { v.pictureFocus = PictureFocus(x: x, y: y) }
        v.alt = alt; v.passes = passes; v.laters = laters; v.doneAt = doneAt; v.droppedAt = droppedAt; v.quietAt = quietAt
        v.loved = loved; v.thoughts = thoughts; v.edited = edited; v.schoolJSON = schoolJSON; v.oldId = oldId
        if emailFrom != nil || emailSubject != nil {
            v.email = EmailInfo(from: emailFrom, fromName: emailFromName, subject: emailSubject, receivedAt: emailReceivedAt)
        }
        return v
    }
}
