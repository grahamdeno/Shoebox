import Foundation
import ShoeboxCore
import SwiftData

/// Bringing saves in (Shoebox 1 backups and this app's own) and keeping a copy safe.
/// Imports only add, and importing the same file twice adds nothing. Daily copies keep the last 7 and the biggest.
@MainActor
enum Backups {
    static let cloudId = "iCloud.com.grahamdeno.shoebox"

    /// The iCloud container, looked up once off the main thread (the lookup can block for seconds).
    private static var cloudRoot: URL?
    private static var cloudResolved = false

    static func resolveCloud() async {
        guard !cloudResolved else { return }
        let id = cloudId
        cloudRoot = await Task.detached { FileManager.default.url(forUbiquityContainerIdentifier: id) }.value
        cloudResolved = true
    }

    /// Documents/Backups here, and the same folder in iCloud Drive once it's known.
    static var folders: [URL] {
        var places: [URL] = []
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            places.append(docs.appending(path: "Backups", directoryHint: .isDirectory))
        }
        if let cloudRoot {
            places.append(cloudRoot.appending(path: "Documents/Backups", directoryHint: .isDirectory))
        }
        return places
    }

    /// A Shoebox 1 backup name from a folder listing. iCloud lists files that aren't downloaded
    /// yet as ".shoebox-backup-2026-10-01.json.icloud"; those count too.
    nonisolated static func oldBackupName(_ listed: String) -> String? {
        var n = listed
        if n.hasPrefix("."), n.hasSuffix(".icloud") { n = String(n.dropFirst().dropLast(".icloud".count)) }
        return n.hasPrefix("shoebox-backup-") && n.hasSuffix(".json") ? n : nil
    }

    /// The newest Shoebox 1 backup (`shoebox-backup-YYYY-MM-DD.json`) in these folders, read.
    /// Runs off the main thread: a coordinated read waits for iCloud to download the file.
    nonisolated static func readNewestOldBackup(in dirs: [URL]) -> Data? {
        var found: [(name: String, url: URL)] = []
        for dir in dirs {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path())) ?? []
            for listed in names {
                guard let n = oldBackupName(listed) else { continue }
                let url = dir.appending(path: n)
                if listed != n { try? FileManager.default.startDownloadingUbiquitousItem(at: url) }
                found.append((n, url))
            }
        }
        guard let newest = found.max(by: { $0.name < $1.name })?.url else { return nil }
        return coordinatedRead(newest)
    }

    nonisolated static func coordinatedRead(_ url: URL) -> Data? {
        var data: Data?
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &err) { data = try? Data(contentsOf: $0) }
        return data ?? (try? Data(contentsOf: url))
    }

    private static var inFlight: Task<String?, Never>?

    /// First launch: bring Shoebox 1's saves over if a backup is on this phone or in iCloud Drive.
    /// Tries again on later launches until one is found. Callers at the same moment share one run.
    static func autoImport(_ context: ModelContext) async -> String? {
        if Prefs.importChecked { return Prefs.importReport }
        if let inFlight { return await inFlight.value }
        let task = Task<String?, Never> { @MainActor in
            await resolveCloud()
            let dirs = folders
            guard let data = await Task.detached(operation: { readNewestOldBackup(in: dirs) }).value,
                  let report = try? importData(data, context) else { return nil }
            Prefs.importChecked = true
            Prefs.importReport = report
            return report
        }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    static func importFile(_ url: URL, _ context: ModelContext) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = coordinatedRead(url) else { throw BackupImporter.Failure.notABackup }
        return try importData(data, context)
    }

    static func importData(_ data: Data, _ context: ModelContext) throws -> String {
        if let mine = try? JSONDecoder.shoebox.decode(Export.self, from: data), mine.app == "shoebox-native" {
            return restore(mine, context)
        }
        let all = (try? context.fetch(FetchDescriptor<Save>())) ?? []
        let existing = Set(all.compactMap(\.oldId))
        let r = try BackupImporter.read(data, options: .init(existingOldIds: existing))
        apply(r, context)
        return report(r.report)
    }

    // MARK: Shoebox 1

    static func apply(_ r: BackupImporter.Result, _ context: ModelContext) {
        let now = Date()
        var pictures: [UUID: Data] = [:]
        for a in r.attachments {
            guard a.mime.hasPrefix("image/"), let data = r.fileData[a.id] else { continue }
            if pictures[a.saveId] == nil || a.role == .picture || a.role == .thumbnail {
                pictures[a.saveId] = Relay.thumbnail(data) ?? data
            }
        }
        var nextMoment: [UUID: Date] = [:]
        for m in r.moments where m.state == .scheduled {
            nextMoment[m.saveId] = min(nextMoment[m.saveId] ?? .distantFuture, m.start)
        }
        for v in r.saves {
            let s = Save(title: v.title, snippet: snippet(v), body: v.text ?? v.extended, note: v.reason,
                         origin: origin(v), kind: kind(v.kind), urlString: v.url, createdAt: v.createdAt)
            if s.title.isEmpty { s.title = String((v.text ?? "").prefix(90)) }
            if v.kind == .quote, let author = v.author { s.snippet = author }
            s.id = v.id
            s.oldId = v.oldId
            s.imageURL = v.imageURL
            s.imageData = pictures[v.id]
            s.enrichedAt = (s.imageData != nil || s.url == nil) ? now : nil
            s.emailFrom = v.email?.from
            s.emailSubject = v.email?.subject
            s.emailReceivedAt = v.email?.receivedAt
            s.updatedAt = v.updatedAt
            switch v.status {
            case .done:
                s.status = .kept
            case .dropped:
                s.status = .kept
                s.deletedAt = v.droppedAt ?? now
            default:
                if let start = nextMoment[v.id], start > now {
                    s.status = .away
                    s.returnDate = start
                } else {
                    s.status = .today
                }
            }
            if v.deletedAt != nil { s.deletedAt = v.deletedAt }
            context.insert(s)
        }
        let st = r.settings
        if Prefs.inboxKey == nil { Prefs.inboxKey = st.inboxKey }
        if Prefs.inboxAddress == nil { Prefs.inboxAddress = st.inboxAddress }
        try? context.save()
    }

    private static func snippet(_ v: SaveValue) -> String {
        for s in [v.summary, v.hook] where !s.isEmpty { return String(s.prefix(280)) }
        if v.kind != .note, let t = v.text, !t.isEmpty { return String(t.prefix(200)) }
        return ""
    }

    private static func origin(_ v: SaveValue) -> String {
        switch v.source {
        case .email, .school: return "via your Shoebox email"
        case .paste: return "a note"
        case .screenshot: return "a screenshot"
        default: return ""
        }
    }

    private static func kind(_ k: ShoeboxCore.SaveKind) -> SaveKind {
        switch k {
        case .link: return .link
        case .note: return .note
        case .quote: return .quote
        case .photo: return .photo
        case .video: return .video
        case .pdf, .file: return .file
        }
    }

    /// "214 saves and your email address came over."
    static func report(_ r: BackupImporter.Report) -> String {
        if r.saves == 0 && r.alreadyHere > 0 { return "Your saves from Shoebox 1 are already here." }
        var parts = ["\(r.saves) \(r.saves == 1 ? "save" : "saves")"]
        if r.files > 0 { parts.append("\(r.files) photos and files") }
        if r.emailAddress { parts.append("your email address") }
        let text = parts.count == 1 ? parts[0] : parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        return text + " came over from Shoebox 1."
    }

    // MARK: This app's own backup

    struct Export: Codable {
        var app = "shoebox-native"
        var format = 1
        var exported = Date()
        var saves: [Item]
        var inboxKey: String?
        var inboxAddress: String?

        struct Item: Codable {
            var id: UUID; var createdAt: Date; var updatedAt: Date; var deletedAt: Date?
            var title: String; var snippet: String; var body: String; var note: String; var origin: String; var source: String
            var kind: String; var url: String?; var imageURL: String?; var image: Data?
            var status: String; var returnDate: Date?; var seenOn: Date?; var eventDate: Date?
            var emailFrom: String?; var emailSubject: String?; var emailReceivedAt: Date?; var oldId: String?
            // Added later; older backups don't have them.
            var eventHasTime: Bool?; var otherDates: String?; var imageSource: String?
        }
    }

    static func export(_ context: ModelContext) -> Data? {
        let all = (try? context.fetch(FetchDescriptor<Save>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let items = all.map { s in
            Export.Item(id: s.id, createdAt: s.createdAt, updatedAt: s.updatedAt, deletedAt: s.deletedAt,
                        title: s.title, snippet: s.snippet, body: s.body, note: s.note, origin: s.origin, source: s.source,
                        kind: s.kindRaw, url: s.urlString, imageURL: s.imageURL, image: s.imageData,
                        status: s.statusRaw, returnDate: s.returnDate, seenOn: s.seenOn, eventDate: s.eventDate,
                        emailFrom: s.emailFrom, emailSubject: s.emailSubject, emailReceivedAt: s.emailReceivedAt, oldId: s.oldId,
                        eventHasTime: s.eventHasTime, otherDates: s.otherDatesRaw, imageSource: s.imageSource)
        }
        let e = Export(saves: items, inboxKey: Prefs.inboxKey, inboxAddress: Prefs.inboxAddress)
        return try? JSONEncoder.shoebox.encode(e)
    }

    static func restore(_ e: Export, _ context: ModelContext) -> String {
        let all = (try? context.fetch(FetchDescriptor<Save>())) ?? []
        let have = Set(all.map(\.id))
        var added = 0
        for i in e.saves where !have.contains(i.id) {
            let s = Save(title: i.title, snippet: i.snippet, body: i.body, note: i.note, source: i.source, origin: i.origin,
                         kind: SaveKind(rawValue: i.kind) ?? .note, urlString: i.url, imageData: i.image,
                         status: SaveStatus(rawValue: i.status) ?? .today, returnDate: i.returnDate, eventDate: i.eventDate,
                         createdAt: i.createdAt)
            s.id = i.id; s.updatedAt = i.updatedAt; s.deletedAt = i.deletedAt; s.seenOn = i.seenOn
            s.imageURL = i.imageURL; s.oldId = i.oldId
            s.emailFrom = i.emailFrom; s.emailSubject = i.emailSubject; s.emailReceivedAt = i.emailReceivedAt
            s.eventHasTime = i.eventHasTime ?? false
            s.otherDatesRaw = i.otherDates ?? ""
            s.imageSource = i.imageSource
            s.enrichedAt = Date()
            context.insert(s)
            added += 1
        }
        if Prefs.inboxKey == nil { Prefs.inboxKey = e.inboxKey }
        if Prefs.inboxAddress == nil { Prefs.inboxAddress = e.inboxAddress }
        try? context.save()
        if added == 0 { return "Everything in that backup is already here." }
        return "\(added) \(added == 1 ? "save" : "saves") came back from the backup."
    }

    /// Once a day: a copy in Documents/Backups and in iCloud Drive, keeping the last 7.
    static func dailyBackup(_ context: ModelContext) {
        let key = TodayRules().dayKey(Date())
        guard AppGroup.defaults.string(forKey: "lastBackup") != key else { return }
        let count = (try? context.fetchCount(FetchDescriptor<Save>())) ?? 0
        guard count > 0, let data = export(context) else { return }
        let name = "shoebox-native-backup-\(key).json"
        var wrote = false
        for dir in folders {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if (try? data.write(to: dir.appending(path: name), options: .atomic)) != nil { wrote = true }
            let mine = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path())) ?? [])
                .filter { $0.hasPrefix("shoebox-native-backup-") }.sorted()
            // Keep the last 7, and always the biggest one, so a store that shrank by accident
            // can't push the good copies out after a week.
            let biggest = mine.max { size(dir.appending(path: $0)) < size(dir.appending(path: $1)) }
            for old in mine.dropLast(7) where old != biggest {
                try? FileManager.default.removeItem(at: dir.appending(path: old))
            }
        }
        if wrote {
            AppGroup.defaults.set(key, forKey: "lastBackup")
            AppGroup.defaults.set(Date(), forKey: "lastBackupAt")
        }
    }

    private static func size(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    /// Writes one copy to every backup folder. True only if at least one copy landed.
    static func writeCopy(_ data: Data, named name: String) -> Bool {
        var wrote = false
        for dir in folders {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if (try? data.write(to: dir.appending(path: name), options: .atomic)) != nil { wrote = true }
        }
        return wrote
    }

    static var lastBackupAt: Date? { AppGroup.defaults.object(forKey: "lastBackupAt") as? Date }
}

extension JSONEncoder {
    static var shoebox: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var shoebox: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
