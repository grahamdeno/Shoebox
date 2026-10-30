import Foundation

// The return planner's public types (docs/SPEC.md section 4).
// The rules do all date arithmetic; the on-device model only supplies hints.

/// A time of day, in the calendar's time zone.
public struct DayTime: Sendable, Equatable, Hashable {
    public var hour: Int
    public var minute: Int
    public init(_ hour: Int, _ minute: Int) { self.hour = hour; self.minute = minute }

    var totalMinutes: Int { hour * 60 + minute }

    func adding(minutes: Int) -> DayTime {
        let t = max(0, min(24 * 60 - 1, totalMinutes + minutes))
        return DayTime(t / 60, t % 60)
    }
}

/// One calendar event, read from EventKit on the phone. Never leaves the device.
public struct CalendarEventInfo: Sendable, Equatable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false) {
        self.id = id; self.title = title; self.start = start; self.end = end; self.isAllDay = isAllDay
    }
}

/// SPEC 4.2 defaults that the person can change.
public struct PlannerSettings: Sendable, Equatable {
    public var weekdayIssue: DayTime
    public var weekendIssue: DayTime
    public var homeEveningStart: DayTime
    public var homeEveningEnd: DayTime
    public var workStart: DayTime
    public var workEnd: DayTime
    /// Saturday's weekend morning.
    public var weekendMorning: DayTime

    public init(weekdayIssue: DayTime = DayTime(7, 0), weekendIssue: DayTime = DayTime(8, 0),
                homeEveningStart: DayTime = DayTime(18, 0), homeEveningEnd: DayTime = DayTime(20, 30),
                workStart: DayTime = DayTime(9, 0), workEnd: DayTime = DayTime(17, 0),
                weekendMorning: DayTime = DayTime(9, 0)) {
        self.weekdayIssue = weekdayIssue; self.weekendIssue = weekendIssue
        self.homeEveningStart = homeEveningStart; self.homeEveningEnd = homeEveningEnd
        self.workStart = workStart; self.workEnd = workEnd
        self.weekendMorning = weekendMorning
    }

    public static let standard = PlannerSettings()
}

/// What the on-device model (or relay) may add when rules alone can't decide. All optional.
public struct ModelHints: Sendable, Equatable {
    /// e.g. "when it gets cold" -> 12
    public var monthHint: Int?
    /// Overnight step, delivery: R11 moves earlier (Sat 8:05 AM).
    public var needsDayAhead: Bool
    /// R20 example 40.
    public var weekendProject: Bool
    /// Relay lookup (peak color) for R15.
    public var bestDate: Date?
    /// The model's pick of a calendar event for R3 when word matching is unsure.
    public var anchorEventId: String?

    public init(monthHint: Int? = nil, needsDayAhead: Bool = false, weekendProject: Bool = false,
                bestDate: Date? = nil, anchorEventId: String? = nil) {
        self.monthHint = monthHint; self.needsDayAhead = needsDayAhead; self.weekendProject = weekendProject
        self.bestDate = bestDate; self.anchorEventId = anchorEventId
    }
}

public struct PlanInput: Sendable {
    public var reason: String
    public var kind: SaveKind
    public var minutes: Int?
    public var intent: Intent?
    public var title: String
    public var now: Date
    public var events: [CalendarEventInfo]
    /// start-of-day -> moments already planned, for R20 "lightest day".
    public var plannedPerDay: [Date: Int]
    public var hints: ModelHints?

    public init(reason: String = "", kind: SaveKind = .link, minutes: Int? = nil, intent: Intent? = nil,
                title: String = "", now: Date = Date(), events: [CalendarEventInfo] = [],
                plannedPerDay: [Date: Int] = [:], hints: ModelHints? = nil) {
        self.reason = reason; self.kind = kind; self.minutes = minutes; self.intent = intent; self.title = title
        self.now = now; self.events = events; self.plannedPerDay = plannedPerDay; self.hints = hints
    }
}

public struct PlannedMoment: Sendable, Equatable {
    public var start: Date
    public var end: Date
    public var surface: MomentSurface
    public var place: MomentPlace
    /// "R1" ... "R22"
    public var ruleId: String
    public var confidence: MomentConfidence
    /// The capture line, at most 60 characters: "Comes back Saturday morning".
    public var explanation: String
    /// The Later button's label, at most 18 characters: "Tomorrow", "Saturday", "After planning", "Tonight".
    public var laterLabel: String
    public var anchorEventId: String?

    public init(start: Date, end: Date, surface: MomentSurface, place: MomentPlace, ruleId: String,
                confidence: MomentConfidence, explanation: String, laterLabel: String, anchorEventId: String? = nil) {
        self.start = start; self.end = end; self.surface = surface; self.place = place; self.ruleId = ruleId
        self.confidence = confidence; self.explanation = explanation; self.laterLabel = laterLabel
        self.anchorEventId = anchorEventId
    }
}

public enum PlanOutcome: Sendable, Equatable {
    case moment(PlannedMoment)
    /// R21 (and school dates in R16): ask once at capture; unanswered, the fallback holds.
    case ask(choices: [String], fallback: PlannedMoment)
    /// R22: offer a Reminders entry; kept as a save, the fallback is its one moment.
    case offerReminder(fallback: PlannedMoment)

    /// The moment, or the fallback.
    public var moment: PlannedMoment {
        switch self {
        case .moment(let m): return m
        case .ask(_, let f): return f
        case .offerReminder(let f): return f
        }
    }
}

public enum LaterChoice: String, CaseIterable, Sendable {
    case tonight, tomorrowMorning, thisWeekend, nextWeek, youChoose
}

public enum ReturnPlanner {
    public static func plan(_ input: PlanInput, settings: PlannerSettings = .standard,
                            calendar: Calendar = .current) -> PlanOutcome {
        PlannerEngine(input, settings, calendar).evaluate().outcome
    }

    /// Later from a moment: the concrete time for each choice, counted from `input.now`.
    public static func later(_ choice: LaterChoice, input: PlanInput, settings: PlannerSettings = .standard,
                             calendar: Calendar = .current) -> PlannedMoment {
        PlannerEngine(input, settings, calendar).later(choice)
    }

    /// Returns true when the text has no time words at all (planner falls to R20), or names a time
    /// the rules can't place (R21), so the app knows to ask the model. Empty text returns false:
    /// there is nothing for the model to read, and the content decides.
    public static func needsModel(_ reason: String) -> Bool {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let engine = PlannerEngine(PlanInput(reason: trimmed, now: Date()), .standard, Calendar(identifier: .gregorian))
        let stage = engine.evaluate().stage
        return stage == .content || stage == .unplaceable
    }
}
