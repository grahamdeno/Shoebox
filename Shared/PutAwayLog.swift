import Foundation

/// When you put each post away, for "Just put away" at the top of Put away (SPEC 2.4).
/// Kept in the App Group's settings, not in the store: the store's model stays as it is, so nothing has to migrate.
/// Only your own put-aways are written (pulling down, or Put away on an opened post). Past events that move to
/// Kept on their own are not. Entries older than a week are dropped whenever one is written.
struct PutAwayLog {
    var defaults: UserDefaults
    var calendar: Calendar = .current
    private static let key = "putAwayAt"

    static var shared: PutAwayLog { PutAwayLog(defaults: AppGroup.defaults) }

    /// How many days count as recent: today and the two before it.
    static let days = 3

    private var entries: [String: Double] {
        get { defaults.dictionary(forKey: Self.key) as? [String: Double] ?? [:] }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
    }

    func at(_ id: UUID) -> Date? {
        entries[id.uuidString].map { Date(timeIntervalSince1970: $0) }
    }

    /// Records the time, or clears it with nil (Undo, Back on Today).
    func set(_ id: UUID, _ date: Date?) {
        var e = entries
        e[id.uuidString] = date?.timeIntervalSince1970
        if let date {
            let week = date.addingTimeInterval(-7 * 86_400).timeIntervalSince1970
            e = e.filter { $0.value >= week }
        }
        entries = e
    }

    /// The start of the oldest day that counts as recent.
    func cutoff(now: Date) -> Date {
        calendar.date(byAdding: .day, value: -(Self.days - 1), to: calendar.startOfDay(for: now)) ?? now
    }

    /// Posts you put away today or in the two days before, still put away and not deleted, newest first.
    func recent(_ all: [Save], now: Date) -> [Save] {
        let e = entries
        let from = cutoff(now: now).timeIntervalSince1970
        return all
            .filter { $0.deletedAt == nil && $0.status == .kept }
            .compactMap { s in e[s.id.uuidString].flatMap { $0 >= from ? (s, $0) : nil } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// "Put away today", "Put away yesterday", "Put away Wednesday".
    func line(_ s: Save, now: Date) -> String {
        guard let d = at(s.id) else { return "Put away" }
        if calendar.isDate(d, inSameDayAs: now) { return "Put away today" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(d, inSameDayAs: y) {
            return "Put away yesterday"
        }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = calendar.locale ?? .current
        f.dateFormat = "EEEE"
        return "Put away " + f.string(from: d)
    }
}
