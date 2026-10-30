import Foundation

/// The Daily Issue: one morning notification with today's few, as your reasons (SPEC 6).
public enum DailyIssue {
    public struct Line: Sendable, Equatable {
        public var saveId: UUID
        public var reason: String
        public var title: String
        public var isSchool: Bool

        public init(saveId: UUID, reason: String, title: String, isSchool: Bool) {
            self.saveId = saveId; self.reason = reason; self.title = title; self.isSchool = isSchool
        }
    }

    public struct Composition: Sendable, Equatable {
        /// Saves first, then school posts. Empty means no Issue today.
        public var lines: [Line]
        /// Saves (then school posts) that didn't fit; they move to the next Issue with room.
        public var overflow: [UUID]
        /// The first line's reason, or its title when it has no reason. "" when there are no lines.
        public var cover: String
        /// "and 2 more" under the cover; nil with one line or none.
        public var more: String?

        public init(lines: [Line], overflow: [UUID], cover: String, more: String?) {
            self.lines = lines; self.overflow = overflow; self.cover = cover; self.more = more
        }
    }

    /// Up to `maxSaves` saves, then up to `maxSchool` school posts, in the order given. Never padded.
    /// A save listed twice is used once.
    public static func compose(saves: [Line], school: [Line], maxSaves: Int = 3, maxSchool: Int = 2) -> Composition {
        var seen = Set<UUID>()
        var keptSaves: [Line] = []
        var keptSchool: [Line] = []
        var overflow: [UUID] = []
        for line in saves where !seen.contains(line.saveId) {
            seen.insert(line.saveId)
            if keptSaves.count < max(0, maxSaves) { keptSaves.append(line) } else { overflow.append(line.saveId) }
        }
        // [Check] School posts over the limit are returned in overflow too, after the saves.
        for line in school where !seen.contains(line.saveId) {
            seen.insert(line.saveId)
            if keptSchool.count < max(0, maxSchool) { keptSchool.append(line) } else { overflow.append(line.saveId) }
        }
        let lines = keptSaves + keptSchool
        var cover = ""
        if let first = lines.first {
            let reason = RulesRegex.trim(first.reason)
            cover = reason.isEmpty ? RulesRegex.trim(first.title) : reason
        }
        let more: String? = lines.count > 1 ? "and \(lines.count - 1) more" : nil
        return Composition(lines: lines, overflow: overflow, cover: cover, more: more)
    }

    /// The Issue's time on a day: 7:00 AM weekdays, 8:00 AM Saturday and Sunday, by default.
    public static func time(on day: Date, weekday: (hour: Int, minute: Int) = (7, 0),
                            weekend: (hour: Int, minute: Int) = (8, 0), calendar: Calendar) -> Date {
        // Saturday and Sunday by weekday number, so the result doesn't depend on the locale's weekend.
        let dayNumber = calendar.component(.weekday, from: day)
        let t = (dayNumber == 1 || dayNumber == 7) ? weekend : weekday
        if let d = calendar.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: day) { return d }
        return calendar.startOfDay(for: day).addingTimeInterval(TimeInterval(t.hour * 3600 + t.minute * 60))
    }
}
