import Foundation
import SwiftData

/// The App Group every part of Shoebox shares: the app and the share sheet read one store.
enum AppGroup {
    static let id = "group.com.grahamdeno.shoebox"

    static var container: URL {
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) { return group }
        let own = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
        return own
    }

    static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }
}

/// Version 1 of the store: the model as of Shoebox 1.0. Before changing `Save` (adding, renaming or removing a
/// property), freeze today's `Save` as a nested copy inside this enum, make the new one version 2, and add a stage
/// to `ShoeboxMigrationPlan`. Never edit the model and ship without a new version: that is how a store stops opening.
enum ShoeboxSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Save.self] }
}

enum ShoeboxMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [ShoeboxSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum Store {
    /// The file the store lives in, in the App Group.
    static var url: URL { AppGroup.container.appending(path: "Shoebox.store") }

    /// One SwiftData store in the App Group. CloudKit is off on purpose: the app has an iCloud
    /// entitlement for reading Shoebox 1's backups, and SwiftData would otherwise try to sync.
    /// `at` is for tests: a store somewhere else.
    static func make(inMemory: Bool = false, at location: URL? = nil) throws -> ModelContainer {
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            config = ModelConfiguration(url: location ?? url, cloudKitDatabase: .none)
        }
        do {
            return try ModelContainer(for: Schema(versionedSchema: ShoeboxSchemaV1.self), migrationPlan: ShoeboxMigrationPlan.self, configurations: config)
        } catch {
            // A store made before versions were recorded has none. It holds the same model, so open it the plain way.
            // Nothing is changed or deleted by trying.
            return try ModelContainer(for: Save.self, configurations: config)
        }
    }

    /// Copies the store files (the database, its journal and the pictures and files kept beside it) into a folder in
    /// Files, and only then removes them from `directory`, so a new empty store can start. Nothing is deleted unless
    /// the copy worked. Returns the folder.
    @discardableResult
    static func setAside(from directory: URL = AppGroup.container, into documents: URL? = nil, now: Date = Date()) throws -> URL {
        let fm = FileManager.default
        let docs = documents ?? fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd HHmmss"
        let dest = docs.appending(path: "Recovered \(stamp.string(from: now))")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        let names = try fm.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix("Shoebox.store") || $0 == ".Shoebox_SUPPORT" }
        for name in names { try fm.copyItem(at: directory.appending(path: name), to: dest.appending(path: name)) }
        for name in names { try fm.removeItem(at: directory.appending(path: name)) }
        return dest
    }
}

/// Small settings, shared with the share sheet.
enum Prefs {
    private static var d: UserDefaults { AppGroup.defaults }

    static var onboarded: Bool {
        get { d.bool(forKey: "onboarded") }
        set { d.set(newValue, forKey: "onboarded") }
    }

    /// How many come out of the box each day.
    /// Dates have been read from the saves kept before dates were read for every save.
    static var datesBackfilled: Bool {
        get { d.bool(forKey: "datesBackfilled1") }
        set { d.set(newValue, forKey: "datesBackfilled1") }
    }

    /// Find a stock picture for posts that have none. On unless turned off in Settings.
    static var stockPictures: Bool {
        get { d.object(forKey: "stockPictures") as? Bool ?? true }
        set { d.set(newValue, forKey: "stockPictures") }
    }

    /// How many come out each day. No limit unless one is chosen in Settings.
    static let noLimit = Int.max
    static var perDay: Int {
        get { let n = d.integer(forKey: "dailyLimit"); return n <= 0 ? noLimit : n }
        set { d.set(newValue == noLimit ? 0 : newValue, forKey: "dailyLimit") }
    }

    /// 0 follows the phone, 1 is always light, 2 is always dark.
    static var appearance: Int {
        get { d.integer(forKey: "appearance") }
        set { d.set(newValue, forKey: "appearance") }
    }

    /// When they come out: minutes after midnight. Default 7:30 AM.
    static var dailyMinute: Int {
        get { d.object(forKey: "dailyMinute") as? Int ?? 450 }
        set { d.set(newValue, forKey: "dailyMinute") }
    }

    static var notificationsOn: Bool {
        get { d.bool(forKey: "notificationsOn") }
        set { d.set(newValue, forKey: "notificationsOn") }
    }

    /// The mailbox secret as earlier builds kept it, in plain defaults. Only `MailboxKeys.migrate` reads this, to move
    /// it into the Keychain. Nothing else may: the secret is read through `MailboxKeys`, never from here.
    static var legacyInboxKey: String? {
        get { d.string(forKey: "inboxKey") }
        set { d.set(newValue, forKey: "inboxKey") }
    }

    /// The address, for display only. The relay is the source of truth for whether it works.
    static var inboxAddress: String? {
        get { d.string(forKey: "inboxAddress") }
        set { d.set(newValue, forKey: "inboxAddress") }
    }

    /// Whether the relay holds this phone's current sealing key. False until the first mint or registration succeeds.
    static var sealingRegistered: Bool {
        get { d.bool(forKey: "sealingRegistered") }
        set { d.set(newValue, forKey: "sealingRegistered") }
    }

    /// When this phone first saw the relay holding a sealing key that is not its own. It waits a day before
    /// registering its own, so a key still on its way through iCloud Keychain is not replaced. Nil when they match.
    static var sealMismatchSince: Date? {
        get { d.object(forKey: "sealMismatchSince") as? Date }
        set { d.set(newValue, forKey: "sealMismatchSince") }
    }

    /// Mail that arrived sealed to a key this phone does not have (a new phone without iCloud Keychain). Counted and
    /// dropped; Settings shows one quiet line for a week after the last one.
    static var unopenedMail: Int {
        get { d.integer(forKey: "unopenedMail") }
        set { d.set(newValue, forKey: "unopenedMail") }
    }

    static var unopenedMailAt: Date? {
        get { d.object(forKey: "unopenedMailAt") as? Date }
        set { d.set(newValue, forKey: "unopenedMailAt") }
    }

    /// The first time this install opened. `.distantPast` for an install that was already in use before this was
    /// recorded. Shoebox Plus is offered a week after it (SPEC 9).
    static var firstOpened: Date? {
        get { d.object(forKey: "firstOpened") as? Date }
        set { d.set(newValue, forKey: "firstOpened") }
    }

    /// Who your mail is about, in your own words ("Sam, 4th grade: soccer, band").
    /// A newsletter with many dates makes posts only for the ones that match.
    static var mailFor: String {
        get { d.string(forKey: "mailFor") ?? "" }
        set { d.set(newValue, forKey: "mailFor") }
    }

    static var importChecked: Bool {
        get { d.bool(forKey: "importChecked") }
        set { d.set(newValue, forKey: "importChecked") }
    }

    static var importReport: String? {
        get { d.string(forKey: "importReport") }
        set { d.set(newValue, forKey: "importReport") }
    }

    /// Today's pick: the day it was made and the ids on it.
    static var pickDay: String? {
        get { d.string(forKey: "pickDay") }
        set { d.set(newValue, forKey: "pickDay") }
    }

    static var pickIds: [String] {
        get { d.stringArray(forKey: "pickIds") ?? [] }
        set { d.set(newValue, forKey: "pickIds") }
    }
}
