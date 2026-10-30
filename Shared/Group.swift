import Foundation

/// The App Group every part of Shoebox shares: the app, the share sheet, the widgets and the Issue view.
enum AppGroup {
    static let id = "group.com.grahamdeno.shoebox"

    static var container: URL {
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) { return group }
        let own = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
        return own
    }

    /// Files and photos, as `Files/<attachment id>.<ext>`.
    static var files: URL {
        let url = container.appending(path: "Files", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func url(forStored fileName: String) -> URL { container.appending(path: fileName) }

    static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }
}
