import Foundation

struct LaterSuggestion: Equatable {
    var date: Date
    var label: String
    var reason: String
}

/// Reads the user's own words and picks a time. Plain rules, no network.
/// The on-device model comes later and falls back to these rules.
struct LaterPlanner {
    var calendar: Calendar = .current

    private static let weekdays: [(String, Int)] = [
        ("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4),
        ("thursday", 5), ("friday", 6), ("saturday", 7),
    ]

    private func next(weekday: Int, hour: Int, after now: Date) -> Date {
        calendar.nextDate(
            after: now,
            matching: DateComponents(hour: hour, minute: 0, weekday: weekday),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(86_400)
    }

    private func tomorrow(hour: Int, now: Date) -> Date {
        let day = calendar.startOfDay(for: now)
        let t = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        return calendar.date(byAdding: .hour, value: hour, to: t) ?? t
    }

    private func today(hour: Int, now: Date) -> Date? {
        let d = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now)
        if let d, d > now { return d }
        return nil
    }

    /// A time the words point to, or nil when they name none.
    func match(words: String, now: Date) -> LaterSuggestion? {
        let text = words.lowercased()
        if text.contains("weekend") {
            let d = next(weekday: 7, hour: 9, after: now)
            return LaterSuggestion(date: d, label: label(for: d, now: now), reason: "you said weekend")
        }
        if text.contains("tonight") || text.contains("dinner") || text.contains("evening") {
            let d = today(hour: 18, now: now) ?? tomorrow(hour: 18, now: now)
            return LaterSuggestion(date: d, label: label(for: d, now: now), reason: "you said evening")
        }
        if text.contains("tomorrow") {
            let d = tomorrow(hour: 8, now: now)
            return LaterSuggestion(date: d, label: "Tomorrow", reason: "you said tomorrow")
        }
        for (name, number) in Self.weekdays where text.contains(name) {
            if text.contains("before \(name)") {
                let before = number == 1 ? 7 : number - 1
                let d = next(weekday: before, hour: 18, after: now)
                return LaterSuggestion(date: d, label: label(for: d, now: now), reason: "you said before \(name.capitalized)")
            }
            let d = next(weekday: number, hour: 8, after: now)
            return LaterSuggestion(date: d, label: label(for: d, now: now), reason: "you mentioned \(name.capitalized)")
        }
        return nil
    }

    /// The suggestion shown first in the Later list.
    func suggestion(for s: Save, now: Date) -> LaterSuggestion {
        if let event = s.eventDate,
           let upcoming = SaveActions(calendar: calendar).reminders(for: event).first(where: { $0 > now }) {
            return LaterSuggestion(date: upcoming, label: label(for: upcoming, now: now), reason: "before the date")
        }
        if let m = match(words: s.note + " " + s.title, now: now) { return m }
        let d = next(weekday: 2, hour: 8, after: now)
        return LaterSuggestion(date: d, label: "Next week", reason: "no date in your note")
    }

    /// When a brand new save first comes back.
    func firstReturn(note: String, now: Date) -> Date {
        match(words: note, now: now)?.date ?? tomorrow(hour: 8, now: now)
    }

    /// The fixed choices under the suggestion.
    func fixedOptions(now: Date) -> [LaterSuggestion] {
        let weekend = next(weekday: 7, hour: 9, after: now)
        let week = next(weekday: 2, hour: 8, after: now)
        return [
            LaterSuggestion(date: weekend, label: "This weekend", reason: ""),
            LaterSuggestion(date: week, label: "Next week", reason: ""),
        ]
    }

    /// Human label for a return date: Tomorrow, This weekend, a weekday, or a date.
    func label(for date: Date, now: Date) -> String {
        let startNow = calendar.startOfDay(for: now)
        let startDate = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startNow, to: startDate).day ?? 0
        if days <= 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        let weekday = calendar.component(.weekday, from: date)
        if days <= 7 && (weekday == 7 || weekday == 1) { return "This weekend" }
        if days <= 7 {
            let f = DateFormatter()
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.locale = calendar.locale ?? Locale(identifier: "en_US")
            f.dateFormat = "EEEE"
            return f.string(from: date)
        }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = calendar.locale ?? Locale(identifier: "en_US")
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}
