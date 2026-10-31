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

enum Store {
    /// One SwiftData store in the App Group. CloudKit is off on purpose: the app has an iCloud
    /// entitlement for reading Shoebox 1's backups, and SwiftData would otherwise try to sync.
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            let url = AppGroup.container.appending(path: "Shoebox.store")
            config = ModelConfiguration(url: url, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: Save.self, configurations: config)
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

    static var inboxKey: String? {
        get { d.string(forKey: "inboxKey") }
        set { d.set(newValue, forKey: "inboxKey") }
    }

    static var inboxAddress: String? {
        get { d.string(forKey: "inboxAddress") }
        set { d.set(newValue, forKey: "inboxAddress") }
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
