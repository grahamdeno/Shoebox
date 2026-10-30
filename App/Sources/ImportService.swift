import Foundation
import ShoeboxCore

/// Brings 1.0's saves over (SPEC 11). Never deletes the old backups or web storage.
@MainActor
enum ImportService {
    /// Newest `shoebox-backup-*.json`: Documents/Backups first, then the iCloud Drive copy.
    static func newestBackup() -> URL? {
        var places: [URL] = []
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            places.append(docs.appending(path: "Backups"))
        }
        if let cloud = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.grahamdeno.shoebox") {
            places.append(cloud.appending(path: "Documents/Backups"))
        }
        for dir in places {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path())) ?? []
            let backups = names.filter { $0.hasPrefix("shoebox-backup-") && $0.hasSuffix(".json") }.sorted()
            if let last = backups.last { return dir.appending(path: last) }
        }
        return nil
    }

    struct Outcome { var text: String; var count: Int }

    /// First launch, and every launch after until it works if 1.0 was ever on this phone.
    static func autoImport(keeper: Keeper) async -> String? {
        guard !Prefs.load().importChecked else { return nil }
        var text: String?
        if let url = newestBackup(), let o = try? importFile(url, keeper: keeper) {
            text = o.text
        } else if LegacyWebImport.mightHaveOldSaves, let data = await LegacyWebImport().run(), let o = try? importData(data, keeper: keeper) {
            text = o.text
        }
        if text != nil || !LegacyWebImport.mightHaveOldSaves { Prefs.update { $0.importChecked = true } }
        return text
    }

    static func importFile(_ url: URL, keeper: Keeper) throws -> Outcome {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try importData(Data(contentsOf: url), keeper: keeper)
    }

    static func importData(_ data: Data, keeper: Keeper) throws -> Outcome {
        if let format3 = try? Exporter.read(data) { return try Exporter.restore(format3, keeper: keeper) }
        let existing = Set(keeper.allSaves(includeDeleted: true).compactMap(\.oldId))
        let p = Prefs.load()
        let r = try BackupImporter.read(data, options: .init(weekdayIssue: (p.weekdayIssue.hour, p.weekdayIssue.minute),
                                                            weekendIssue: (p.weekendIssue.hour, p.weekendIssue.minute),
                                                            existingOldIds: existing))
        apply(r, keeper: keeper)
        return Outcome(text: report(r.report), count: r.report.saves)
    }

    static func apply(_ r: BackupImporter.Result, keeper: Keeper) {
        let ctx = keeper.context
        var saves: [UUID: Save] = [:]
        for v in r.saves {
            let s = Save(v)
            ctx.insert(s)
            saves[v.id] = s
        }
        for a in r.attachments {
            guard let data = r.fileData[a.id] else { continue }
            do { try data.write(to: AppGroup.url(forStored: a.fileName), options: .atomic) } catch { continue }
            ctx.insert(Attachment(a))
        }
        for m in r.moments {
            ctx.insert(Moment(m))
            saves[m.saveId]?.nextMomentId = m.id
        }
        for e in r.events {
            ctx.insert(MomentEvent(saveId: e.saveId, momentId: e.momentId, type: e.type, at: e.at, surface: "import", detail: e.detail))
        }
        let s = r.settings
        Prefs.update { p in
            p.inboxKey = p.inboxKey ?? s.inboxKey
            p.inboxAddress = p.inboxAddress ?? s.inboxAddress
            p.aiConsent = p.aiConsent ?? s.aiConsent
            p.aiDevice = p.aiDevice ?? s.aiDevice
            p.aiToken = p.aiToken ?? s.aiToken
            p.aiAttested = p.aiAttested ?? s.aiAttested
            p.statsOff = p.statsOff || s.statsOff
            if let sc = s.school {
                p.schoolOn = sc.on ?? p.schoolOn
                p.schoolChild = sc.child ?? p.schoolChild
                p.schoolName = sc.school ?? p.schoolName
                p.schoolAbout = sc.about ?? p.schoolAbout
                p.schoolWords = sc.words ?? p.schoolWords
                p.schoolDays = sc.days ?? p.schoolDays
            }
        }
        try? ctx.save()
    }

    /// "214 saves, 37 photos and files, your email address and settings came over."
    static func report(_ r: BackupImporter.Report) -> String {
        if r.saves == 0 && r.alreadyHere > 0 { return "Your saves from Shoebox 1 are already here." }
        var parts = ["\(r.saves) \(r.saves == 1 ? "save" : "saves")"]
        if r.files > 0 { parts.append("\(r.files) photos and files") }
        if r.emailAddress { parts.append("your email address") }
        if r.settings > 0 { parts.append("settings") }
        var text: String
        if parts.count == 1 { text = parts[0] }
        else { text = parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1] }
        text += " came over."
        if r.missingFiles > 0 { text += " \(r.missingFiles) \(r.missingFiles == 1 ? "file was" : "files were") missing from the backup; those saves came without them." }
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
