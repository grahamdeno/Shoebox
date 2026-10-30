import Foundation

/// SPEC 7.6: a post with a date comes back in steps. Something to do or decide: 5 days before (Issue),
/// the evening before (home evening), the day itself (Issue). Something that happens: the evening before only.
public enum DatedSteps {
    public enum Kind: Sendable, Equatable { case todo, happening }

    public enum Step: String, Sendable, CaseIterable { case fiveDays = "step-5", eveningBefore = "step-eve", dayOf = "step-0", first = "step-first" }

    /// The next step after `now` for a target day, or nil when none is left. `isNew` is true when the post
    /// has just arrived: a to-do under 5 days away then begins at the next Issue, if that comes first.
    public static func next(target: Date, kind: Kind, now: Date, isNew: Bool = false, settings: PlannerSettings = .standard,
                            calendar: Calendar = .current) -> PlannedMoment? {
        let day = calendar.startOfDay(for: target)
        let steps = all(day: day, kind: kind, settings: settings, calendar: calendar)
        guard let firstAhead = steps.first(where: { $0.start > now }) else { return nil }
        if isNew, kind == .todo, firstAhead.ruleId != Step.fiveDays.rawValue,
           let issue = nextIssue(after: now, settings: settings, calendar: calendar),
           issue < firstAhead.start, calendar.startOfDay(for: issue) < day {
            return moment(issue, surface: .issue, rule: .first, explanation: "Comes back " + dayWords(issue, calendar),
                          later: label(after: issue, steps: steps), calendar: calendar)
        }
        return firstAhead
    }

    public static func isLast(_ m: PlannedMoment, target: Date, kind: Kind, settings: PlannerSettings = .standard, calendar: Calendar = .current) -> Bool {
        next(target: target, kind: kind, now: m.start, settings: settings, calendar: calendar) == nil
    }

    static func all(day: Date, kind: Kind, settings: PlannerSettings, calendar: Calendar) -> [PlannedMoment] {
        var out: [PlannedMoment] = []
        let before = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        let eveningStart = at(settings.homeEveningStart, on: before, calendar).addingTimeInterval(30 * 60)
        let evening = moment(eveningStart, surface: .notification, rule: .eveningBefore, explanation: "Back the evening before",
                             later: kind == .todo ? "Day of" : "Tomorrow", calendar: calendar,
                             end: at(settings.homeEveningEnd, on: before, calendar))
        if kind == .todo {
            if let five = calendar.date(byAdding: .day, value: -5, to: day) {
                let t = issue(on: five, settings: settings, calendar: calendar)
                out.append(moment(t, surface: .issue, rule: .fiveDays, explanation: "Back 5 days before", later: "Evening before", calendar: calendar))
            }
            out.append(evening)
            let t = issue(on: day, settings: settings, calendar: calendar)
            out.append(moment(t, surface: .issue, rule: .dayOf, explanation: "Back the day of", later: "Tomorrow", calendar: calendar))
        } else {
            out.append(evening)
        }
        return out
    }

    private static func label(after date: Date, steps: [PlannedMoment]) -> String {
        guard let n = steps.first(where: { $0.start > date }) else { return "Tomorrow" }
        switch n.ruleId {
        case Step.eveningBefore.rawValue: return "Evening before"
        case Step.dayOf.rawValue: return "Day of"
        default: return "5 days before"
        }
    }

    static func issue(on day: Date, settings: PlannerSettings, calendar: Calendar) -> Date {
        at(calendar.isDateInWeekend(day) ? settings.weekendIssue : settings.weekdayIssue, on: day, calendar)
    }

    static func nextIssue(after now: Date, settings: PlannerSettings, calendar: Calendar) -> Date? {
        for add in 0...2 {
            guard let d = calendar.date(byAdding: .day, value: add, to: now) else { continue }
            let t = issue(on: d, settings: settings, calendar: calendar)
            if t > now { return t }
        }
        return nil
    }

    static func at(_ t: DayTime, on day: Date, _ calendar: Calendar) -> Date {
        calendar.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: day) ?? day
    }

    private static func dayWords(_ d: Date, _ calendar: Calendar) -> String {
        calendar.isDateInTomorrow(d) ? "tomorrow morning" : "in the next Issue"
    }

    private static func moment(_ start: Date, surface: MomentSurface, rule: Step, explanation: String, later: String,
                               calendar: Calendar, end: Date? = nil) -> PlannedMoment {
        let close = end ?? (surface == .issue ? (calendar.date(bySettingHour: 23, minute: 59, second: 0, of: start) ?? start) : start.addingTimeInterval(3 * 3600))
        return PlannedMoment(start: start, end: max(close, start.addingTimeInterval(60)), surface: surface, place: surface == .notification ? .homeEvening : .any,
                             ruleId: rule.rawValue, confidence: .sure, explanation: explanation, laterLabel: later)
    }
}
