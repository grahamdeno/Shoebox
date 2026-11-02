import Foundation
import MetricKit

/// Crash, hang and launch reports from the system (MetricKit), kept on this phone only. Nothing is sent anywhere:
/// the files are for you to read, and Apple's own crash reports reach you through TestFlight and App Store Connect.
/// The newest 20 are kept.
final class Diagnostics: NSObject, MXMetricManagerSubscriber {
    static let shared = Diagnostics()
    static let keep = 20

    func start() { MXMetricManager.shared.add(self) }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for p in payloads { Self.write(p.jsonRepresentation(), kind: "metrics") }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for p in payloads { Self.write(p.jsonRepresentation(), kind: "diagnostics") }
    }

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Diagnostics")
    }

    /// File names sort oldest first (they start with the date), so no file dates are read.
    static func name(kind: String, now: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return "\(f.string(from: now))-\(kind)-\(UUID().uuidString.prefix(6)).json"
    }

    /// The names to delete so that only the newest `keep` remain.
    static func oldest(in names: [String], keep: Int = Diagnostics.keep) -> [String] {
        let json = names.filter { $0.hasSuffix(".json") }.sorted()
        return json.count > keep ? Array(json.prefix(json.count - keep)) : []
    }

    private static func write(_ data: Data, kind: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: folder.appending(path: name(kind: kind)), options: .atomic)
        let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        for old in oldest(in: names) { try? fm.removeItem(at: folder.appending(path: old)) }
    }
}
