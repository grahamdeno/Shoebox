import Foundation

/// Collisions and the daily budget (SPEC 4.6, itself marked [Check]).
public enum DailyBudget {
    /// At most 4 Shoebox notifications a day, the Issue included. Live Activities count as one each.
    public static let maxPerDay = 4
    /// Timed notifications at least 2 hours apart, unless tied to a calendar event.
    public static let minGap: TimeInterval = 2 * 3600
    /// How far a moment may move to find a free slot of the same kind.
    public static let maxDaysLater = 2

    public struct Slot: Sendable, Equatable {
        public var start: Date
        /// Tied to a calendar event (R3, R4).
        public var anchored: Bool
        public var surface: MomentSurface

        public init(start: Date, anchored: Bool, surface: MomentSurface) {
            self.start = start; self.anchored = anchored; self.surface = surface
        }
    }

    public enum Placement: Sendable, Equatable {
        /// Fine where it is.
        case keep
        /// Becomes a line in the candidate day's Issue (`issueTime`).
        case joinIssue
        /// Moves to this time: the same clock time a day or two later (same surface), or, when
        /// those are full, the next Issue still ahead (the date is that Issue's time).
        case move(Date)
    }

    /// Where a planned moment should land given the moments already planned.
    ///
    /// - Parameters:
    ///   - candidate: the moment being placed.
    ///   - existing: every other planned moment (leave out the candidate's own earlier moment).
    ///     Include an `.issue` slot for any day whose Issue will go out, so it counts toward the 4.
    ///   - issueTime: the Issue time on the candidate's day.
    ///   - now: when the planning runs.
    ///   - issueOn: the Issue time for any day; defaults to `DailyIssue.time(on:calendar:)` with default hours.
    public static func place(_ candidate: Slot, existing: [Slot], issueTime: Date, now: Date, calendar: Calendar,
                             issueOn: ((Date) -> Date)? = nil) -> Placement {
        // Calendar-anchored moments win over everything else.
        if candidate.anchored { return .keep }
        // [Check] An Issue line never breaks the budget: the Issue is one notification however many lines
        // it has, and DailyIssue.compose sends extra lines on to the next Issue.
        if candidate.surface == .issue { return .keep }
        if fits(candidate.start, existing: existing, calendar: calendar) { return .keep }
        // Joins that day's Issue if it can still make it, that is, the Issue hasn't gone out yet.
        if now < issueTime { return .joinIssue }
        // [Check] "Next free slot of the same kind" is read as the same clock time on each of the next
        // two days, so an evening moment stays an evening moment.
        for days in 1...maxDaysLater {
            guard let t = calendar.date(byAdding: .day, value: days, to: candidate.start) else { continue }
            if t > now && fits(t, existing: existing, calendar: calendar) { return .move(t) }
        }
        // [Check] "Past that, it goes to the next Issue" is read as the next Issue still ahead of now
        // (usually tomorrow's), since an Issue line takes no slot of its own.
        let issueAt: (Date) -> Date = issueOn ?? { DailyIssue.time(on: $0, calendar: calendar) }
        var day = calendar.startOfDay(for: now)
        for _ in 0..<8 {
            let t = issueAt(day)
            if t > now { return .move(t) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return .move(issueAt(now.addingTimeInterval(24 * 3600)))
    }

    /// Whether a timed notification at `t` keeps both rules.
    static func fits(_ t: Date, existing: [Slot], calendar: Calendar) -> Bool {
        let sameDay = existing.filter { calendar.isDate($0.start, inSameDayAs: t) }
        let timed = sameDay.filter { $0.surface != .issue }.count
        let issue = sameDay.contains { $0.surface == .issue } ? 1 : 0
        if timed + issue + 1 > maxPerDay { return false }
        // [Check] The gap rule applies between timed notifications only: the Issue and
        // calendar-anchored moments don't push others away (but they do count toward the 4).
        let tooClose = existing.contains { other in
            other.surface != .issue && !other.anchored && abs(other.start.timeIntervalSince(t)) < minGap
        }
        return !tooClose
    }
}
