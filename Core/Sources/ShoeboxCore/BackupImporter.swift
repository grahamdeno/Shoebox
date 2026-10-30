import Foundation
import CryptoKit

/// Reads the old app's backup (`{app:"edition", version:1|2, items, meta, files, settings}`)
/// and maps it as docs/SPEC.md section 11.4 says. Pure: it returns values and writes nothing.
public enum BackupImporter {

    public struct Options: Sendable {
        public var now: Date
        public var calendar: Calendar
        /// Issue time on weekdays and weekends (SPEC 1.6).
        public var weekdayIssue: (hour: Int, minute: Int)
        public var weekendIssue: (hour: Int, minute: Int)
        /// Old ids already in the store, so importing twice adds nothing.
        public var existingOldIds: Set<String>

        public init(now: Date = Date(), calendar: Calendar = .current,
                    weekdayIssue: (hour: Int, minute: Int) = (7, 0), weekendIssue: (hour: Int, minute: Int) = (8, 0),
                    existingOldIds: Set<String> = []) {
            self.now = now; self.calendar = calendar
            self.weekdayIssue = weekdayIssue; self.weekendIssue = weekendIssue
            self.existingOldIds = existingOldIds
        }
    }

    public struct Report: Equatable, Sendable {
        public var saves = 0
        public var alreadyHere = 0
        public var samplesSkipped = 0
        public var files = 0
        public var missingFiles = 0
        public var settings = 0
        public var emailAddress = false
        public var aiSignUp = false
    }

    public struct SchoolSettings: Codable, Equatable, Sendable {
        public var on: Bool?; public var child: String?; public var school: String?; public var about: String?
        public var words: [String]?; public var days: [Int]?
    }

    public struct Settings: Equatable, Sendable {
        public var inboxKey: String?
        public var inboxAddress: String?
        public var aiConsent: String?
        public var aiDevice: String?
        public var aiToken: String?
        public var aiAttested: String?
        public var statsOff: Bool
        public var school: SchoolSettings?
        public var raw: [String: String]
    }

    public struct Result: Sendable {
        public var saves: [SaveValue]
        public var attachments: [AttachmentValue]
        public var fileData: [UUID: Data]      // attachment id -> bytes
        public var moments: [MomentValue]
        public var events: [EventValue]
        public var settings: Settings
        public var report: Report
    }

    public enum Failure: Error, LocalizedError, Equatable {
        case notABackup
        public var errorDescription: String? { "That file isn't a Shoebox backup." }
    }

    // MARK: Entry

    public static func read(_ data: Data, options: Options = Options()) throws -> Result {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (root["app"] as? String) == "edition",
              let items = root["items"] as? [[String: Any]] else { throw Failure.notABackup }

        var report = Report()
        var files: [String: (mime: String, data: Data)] = [:]
        for f in (root["files"] as? [[String: Any]]) ?? [] {
            guard let id = f["id"] as? String, let b64 = f["data"] as? String,
                  let bytes = Data(base64Encoded: b64) else { continue }
            files[id] = ((f["type"] as? String) ?? "", bytes)
        }

        var out = Result(saves: [], attachments: [], fileData: [:], moments: [], events: [],
                         settings: readSettings(root["settings"] as? [String: Any] ?? [:]), report: report)

        for item in items {
            guard let oldId = item["id"].flatMap(asString) else { continue }
            if bool(item["sample"]) { report.samplesSkipped += 1; continue }
            if options.existingOldIds.contains(oldId) { report.alreadyHere += 1; continue }
            map(item, oldId: oldId, files: files, options: options, into: &out, report: &report)
        }
        report.settings = out.settings.raw.count
        report.emailAddress = out.settings.inboxAddress != nil
        report.aiSignUp = out.settings.aiToken != nil
        out.report = report
        return out
    }

    // MARK: One item

    private static let day: TimeInterval = 86_400
    private static let fadeDays: TimeInterval = 21

    private static func map(_ item: [String: Any], oldId: String, files: [String: (mime: String, data: Data)],
                            options: Options, into out: inout Result, report: inout Report) {
        let now = options.now
        let created = date(item["created"]) ?? now
        var s = SaveValue(now: now, kind: kind(item["kind"] as? String), reason: "", source: .import, status: .unplanned)
        s.createdAt = created
        s.oldId = oldId

        let why = clip((item["why"] as? String) ?? "", 140)
        s.reason = why
        s.reasonSource = .imported
        s.title = clip((item["title"] as? String) ?? "Untitled", 140)
        s.text = item["text"] as? String
        s.url = item["url"] as? String
        s.author = item["author"] as? String
        s.videoId = item["videoId"] as? String
        s.imageURL = item["imageUrl"] as? String
        s.summary = clip((item["summary"] as? String) ?? "", 200)
        s.hook = clip((item["hook"] as? String) ?? "", 70)
        s.points = Array(((item["points"] as? [Any]) ?? []).compactMap(asString).prefix(3))
        s.extended = clip((item["extended"] as? String) ?? "", 1800)
        s.transcript = clip((item["transcript"] as? String) ?? "", 1500)
        s.tags = Array(((item["tags"] as? [Any]) ?? []).compactMap(asString).map { clip($0.lowercased(), 32) }.prefix(6))
        s.minutes = (item["minutes"] as? NSNumber).map { $0.intValue }
        s.intent = (item["intent"] as? String).flatMap(Intent.init(rawValue:))
        if let b = item["book"] as? [String: Any], let t = b["title"] as? String {
            s.book = Book(title: t, author: (b["author"] as? String) ?? "")
        }
        if let f = item["focus"] as? [String: Any], let x = double(f["x"]), let y = double(f["y"]) {
            s.pictureFocus = PictureFocus(x: x, y: y)
        }
        s.alt = clip((item["imageAlt"] as? String) ?? "", 160)
        s.loved = bool(item["loved"])
        s.thoughts = ((item["replies"] as? [[String: Any]]) ?? []).compactMap { r in
            guard let t = r["text"] as? String else { return nil }
            return Thought(at: date(r["at"]) ?? created, text: t)
        }
        if bool(item["titleMine"]) || item["editedAt"] != nil { s.edited.insert(.title) }
        if bool(item["tagsMine"]) { s.edited.insert(.tags) }
        if let school = item["school"], JSONSerialization.isValidJSONObject(school),
           let d = try? JSONSerialization.data(withJSONObject: school, options: [.sortedKeys]) {
            s.schoolJSON = String(data: d, encoding: .utf8)
        }
        if let e = item["email"] as? [String: Any] {
            s.email = EmailInfo(from: e["from"] as? String, fromName: e["fromName"] as? String,
                                subject: e["subject"] as? String, receivedAt: date(e["receivedAt"]))
        }

        // Status (SPEC 11.4).
        let old = (item["status"] as? String) ?? "inbox"
        let touched = max(num(item["queuedAt"]), num(item["deferredAt"]), num(item["created"]))
        let faded = item["fadedAt"] != nil || (now.timeIntervalSince1970 * 1000 - touched) >= fadeDays * day * 1000
        var asideMoment: MomentValue?
        switch old {
        case "done":
            s.status = .done; s.doneAt = date(item["doneAt"]) ?? now
        case "archived":
            if bool(item["washedOut"]) { s.status = .quiet; s.quietAt = date(item["archivedAt"]) ?? now }
            else { s.status = .dropped; s.droppedAt = date(item["archivedAt"]) ?? now }
        case "queued":
            if faded { s.status = .quiet; s.quietAt = now } else { s.status = .unplanned }
        case "aside":
            let start = issueStart(onOrAfter: date(item["until"]) ?? now, options: options)
            s.status = .planned
            asideMoment = moment(for: s.id, start: start, options: options)
        default:
            s.status = .unplanned
        }
        // Suggestions from the old top stories and suggestions are not in v1.
        if bool(item["suggested"]) && s.status != .done {
            s.status = .dropped; s.droppedAt = s.droppedAt ?? now; s.quietAt = nil
        }
        // A school post whose date has passed is no longer worth offering.
        if let school = item["school"] as? [String: Any], let d = school["date"] as? String, !d.isEmpty,
           d < dayString(now, options.calendar), s.status == .unplanned || s.status == .planned {
            s.status = .quiet; s.quietAt = now; asideMoment = nil
        }
        if let m = asideMoment { out.moments.append(m) }

        // History -> events.
        for h in (item["history"] as? [[String: Any]]) ?? [] {
            guard let v = h["v"] as? String, let type = eventType(v) else { continue }
            out.events.append(EventValue(id: UUID(), saveId: s.id, momentId: nil, type: type,
                                         at: date(h["at"]) ?? created, detail: nil))
        }

        // Files: original, then thumbnail.
        for (key, role) in [("blobId", AttachmentRole.original), ("thumbId", .thumbnail)] {
            guard let fid = item[key].flatMap(asString) else { continue }
            guard let f = files[fid] else { report.missingFiles += 1; continue }
            let aid = UUID()
            let ext = fileExtension(mime: f.mime, name: item["fileName"] as? String)
            out.attachments.append(AttachmentValue(id: aid, saveId: s.id, role: role,
                fileName: "Files/\(aid.uuidString.lowercased()).\(ext)", mime: f.mime, size: f.data.count,
                sha256: SHA256.hash(data: f.data).map { String(format: "%02x", $0) }.joined(), createdAt: created))
            out.fileData[aid] = f.data
            report.files += 1
        }

        out.saves.append(s)
        report.saves += 1
    }

    // MARK: Settings

    private static func readSettings(_ raw: [String: Any]) -> Settings {
        var strings: [String: String] = [:]
        for (k, v) in raw where k.hasPrefix("edition.") { if let s = v as? String { strings[k] = s } }
        var school: SchoolSettings?
        if let j = strings["edition.school"]?.data(using: .utf8) { school = try? JSONDecoder().decode(SchoolSettings.self, from: j) }
        func nonEmpty(_ k: String) -> String? { strings[k].flatMap { $0.isEmpty ? nil : $0 } }
        return Settings(inboxKey: nonEmpty("edition.inboxKey"), inboxAddress: nonEmpty("edition.inboxAddress"),
                        aiConsent: nonEmpty("edition.aiConsent"), aiDevice: nonEmpty("edition.aiDevice"),
                        aiToken: nonEmpty("edition.aiToken"), aiAttested: nonEmpty("edition.aiAttested"),
                        statsOff: ["1", "true"].contains(strings["edition.statsOff"] ?? ""), school: school, raw: strings)
    }

    // MARK: Helpers

    static func kind(_ s: String?) -> SaveKind { s.flatMap(SaveKind.init(rawValue:)) ?? .file }  // text and audio become file

    static func eventType(_ v: String) -> EventType? {
        switch v {
        case "let-go": return .dropped
        case "later", "aside": return .later
        case "done", "read-now": return .done
        default: return nil
        }
    }

    /// The Issue time on `day` if it is today or later, otherwise the next Issue after now.
    static func issueStart(onOrAfter target: Date, options: Options) -> Date {
        let cal = options.calendar
        func issue(on d: Date) -> Date {
            let weekend = cal.isDateInWeekend(d)
            let t = weekend ? options.weekendIssue : options.weekdayIssue
            return cal.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: d) ?? d
        }
        var candidate = issue(on: max(target, options.now))
        if candidate <= options.now {
            candidate = issue(on: cal.date(byAdding: .day, value: 1, to: candidate) ?? candidate)
        }
        return candidate
    }

    private static func moment(for saveId: UUID, start: Date, options: Options) -> MomentValue {
        let f = DateFormatter(); f.dateFormat = "EEEE"; f.calendar = options.calendar; f.timeZone = options.calendar.timeZone
        return MomentValue(id: UUID(), saveId: saveId, start: start, end: start.addingTimeInterval(day),
                           surface: .issue, place: .any, ruleId: "imported", confidence: .guess,
                           explanation: "Comes back \(f.string(from: start))", laterLabel: "Tomorrow",
                           state: .scheduled, createdAt: options.now)
    }

    private static func dayString(_ d: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func fileExtension(mime: String, name: String?) -> String {
        if let n = name, let e = n.split(separator: ".").last, e.count <= 5, n.contains(".") { return e.lowercased() }
        switch mime {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/heic": return "heic"
        case "application/pdf": return "pdf"
        case "text/plain": return "txt"
        default: return "bin"
        }
    }

    private static func clip(_ s: String, _ n: Int) -> String { s.count > n ? String(s.prefix(n)) : s }
    private static func asString(_ v: Any) -> String? { if let s = v as? String { return s }; if let n = v as? NSNumber { return n.stringValue }; return nil }
    private static func bool(_ v: Any?) -> Bool { (v as? Bool) ?? ((v as? NSNumber)?.boolValue ?? false) }
    private static func num(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? 0 }
    private static func double(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
    private static func date(_ v: Any?) -> Date? {
        guard let n = v as? NSNumber, n.doubleValue > 0 else { return nil }
        return Date(timeIntervalSince1970: n.doubleValue / 1000)
    }
}
