import Foundation
import Testing
@testable import ShoeboxCore

/// One row of docs/SPEC.md 4.4, with the expected start in New York time.
struct PlannerExample: Sendable, CustomTestStringConvertible {
    var n: Int
    var reason: String
    var kind: SaveKind
    var minutes: Int?
    var title: String
    var hints: ModelHints?
    var now: Date
    var year: Int, month: Int, day: Int, hour: Int, minute: Int
    var surface: MomentSurface
    var rule: String

    var testDescription: String { "#\(n) \(reason.isEmpty ? "(no reason)" : reason)" }
}

struct PlannerTests {
    // Wed Nov 4 2026, 2:00 PM in New York.
    static let now = Date(timeIntervalSince1970: 1_793_818_800)
    static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    static func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min
        return cal.date(from: c)!
    }

    /// The SPEC 4.4 calendar. The flight "(trip through Fri Nov 27)" is modeled as two events:
    /// the 8:15 flight and an all-day "Denver trip" from Nov 23 to Nov 27.
    static var events: [CalendarEventInfo] {
        [
            CalendarEventInfo(id: "planning", title: "Quarterly planning", start: at(2026, 11, 5, 10), end: at(2026, 11, 5, 11)),
            CalendarEventInfo(id: "concert", title: "Band concert", start: at(2026, 11, 6, 19), end: at(2026, 11, 6, 20, 30)),
            CalendarEventInfo(id: "sprint", title: "Sprint review", start: at(2026, 11, 10, 14), end: at(2026, 11, 10, 15)),
            CalendarEventInfo(id: "camping", title: "Camping, Carolina Beach", start: at(2026, 11, 14), end: at(2026, 11, 16), isAllDay: true),
            CalendarEventInfo(id: "birthday", title: "Sam's birthday", start: at(2026, 11, 21), end: at(2026, 11, 22), isAllDay: true),
            CalendarEventInfo(id: "flight", title: "Flight to Denver", start: at(2026, 11, 23, 8, 15), end: at(2026, 11, 23, 11, 30)),
            CalendarEventInfo(id: "denver", title: "Denver trip", start: at(2026, 11, 23), end: at(2026, 11, 28), isAllDay: true),
        ]
    }

    static func ex(_ n: Int, _ reason: String, _ kind: SaveKind, _ minutes: Int?,
                   _ when: (Int, Int, Int, Int, Int), _ surface: MomentSurface, _ rule: String,
                   title: String = "", hints: ModelHints? = nil, now: Date = PlannerTests.now) -> PlannerExample {
        PlannerExample(n: n, reason: reason, kind: kind, minutes: minutes, title: title, hints: hints, now: now,
                       year: when.0, month: when.1, day: when.2, hour: when.3, minute: when.4,
                       surface: surface, rule: rule)
    }

    static let examples: [PlannerExample] = [
        ex(1, "Read before we plan next quarter", .link, 11, (2026, 11, 5, 9, 48), .liveActivity, "R3"),
        ex(2, "For Thursday's meeting", .link, 6, (2026, 11, 5, 9, 53), .liveActivity, "R3"),
        ex(3, "Bring this up when tech debt comes up at sprint review", .link, 4, (2026, 11, 10, 13, 55), .liveActivity, "R3"),
        ex(4, "Show the kids at dinner", .photo, nil, (2026, 11, 4, 18, 10), .notification, "R10"),
        ex(5, "At dinner", .link, nil, (2026, 11, 5, 18, 10), .notification, "R10",
           now: Date(timeIntervalSince1970: 1_793_818_800 + 4 * 3600 + 45 * 60)),
        ex(6, "Tonight", .video, 12, (2026, 11, 4, 19, 30), .notification, "R8"),
        ex(7, "After the kids are in bed", .video, 40, (2026, 11, 4, 20, 30), .notification, "R8"),
        ex(8, "At lunch", .link, 6, (2026, 11, 5, 12, 15), .notification, "R8"),
        ex(9, "Tomorrow", .note, nil, (2026, 11, 5, 7, 0), .issue, "R9"),
        ex(10, "Tomorrow night", .link, nil, (2026, 11, 5, 19, 30), .notification, "R9"),
        ex(11, "Friday", .link, nil, (2026, 11, 6, 7, 0), .issue, "R7"),
        ex(12, "Tuesday", .link, nil, (2026, 11, 10, 7, 0), .issue, "R7"),
        ex(13, "Next Tuesday", .link, nil, (2026, 11, 10, 7, 0), .issue, "R7"),
        ex(14, "This weekend", .link, 20, (2026, 11, 7, 9, 0), .notification, "R11"),
        ex(15, "Try the long cold ferment this weekend", .link, nil, (2026, 11, 7, 8, 5), .notification, "R11",
           title: "Sourdough with a long cold ferment", hints: ModelHints(needsDayAhead: true)),
        ex(16, "Watch with Kate this weekend", .video, 95, (2026, 11, 7, 19, 30), .notification, "R11"),
        ex(17, "Next weekend", .link, nil, (2026, 11, 13, 19, 30), .notification, "R12"),
        ex(18, "Next week", .link, nil, (2026, 11, 9, 7, 0), .issue, "R13"),
        ex(19, "In two weeks", .note, nil, (2026, 11, 18, 7, 0), .issue, "R2"),
        ex(20, "In an hour", .note, nil, (2026, 11, 4, 15, 0), .notification, "R2"),
        ex(21, "7pm", .note, nil, (2026, 11, 4, 19, 0), .notification, "R1"),
        ex(22, "Call about Nov 20", .note, nil, (2026, 11, 20, 7, 0), .issue, "R6"),
        ex(23, "Register by Nov 20", .link, nil, (2026, 11, 18, 7, 0), .issue, "R6"),
        ex(24, "Gift idea for Sam's birthday", .link, nil, (2026, 11, 11, 7, 0), .issue, "R5"),
        ex(25, "Read on the plane", .pdf, 40, (2026, 11, 22, 19, 30), .notification, "R4"),
        ex(26, "For the Denver trip", .link, nil, (2026, 11, 16, 7, 0), .issue, "R3"),
        ex(27, "Make this for Thanksgiving", .link, nil, (2026, 11, 21, 9, 0), .notification, "R16",
           title: "Cranberry sauce"),
        ex(28, "Before Christmas", .link, nil, (2026, 12, 11, 7, 0), .issue, "R16",
           title: "Gift: wool blanket for Mom"),
        ex(29, "End of the month", .note, nil, (2026, 11, 30, 7, 0), .issue, "R14"),
        ex(30, "Next month", .link, nil, (2026, 12, 1, 7, 0), .issue, "R14"),
        ex(31, "In March", .link, nil, (2027, 3, 1, 7, 0), .issue, "R14"),
        ex(32, "Next quarter", .link, nil, (2027, 1, 4, 7, 0), .issue, "R17"),
        ex(33, "Drive it next fall", .link, nil, (2027, 10, 16, 9, 0), .notification, "R15",
           title: "Blue Ridge Parkway", hints: ModelHints(bestDate: PlannerTests.at(2027, 10, 16, 12))),
        ex(34, "Next spring", .link, nil, (2027, 3, 20, 9, 0), .notification, "R15", title: "A garden plan"),
        ex(35, "This summer", .link, nil, (2027, 6, 26, 9, 0), .notification, "R15"),
        ex(36, "Monday at work", .link, nil, (2026, 11, 9, 9, 30), .notification, "R18"),
        ex(37, "Pick up at Costco", .note, nil, (2026, 11, 7, 10, 30), .notification, "R19"),
        ex(38, "Someday", .link, nil, (2026, 12, 5, 8, 0), .issue, "R20"),
        ex(39, "", .link, 6, (2026, 11, 6, 7, 0), .issue, "R20"),
        ex(40, "", .link, 35, (2026, 11, 7, 9, 0), .notification, "R20", hints: ModelHints(weekendProject: true)),
        ex(41, "Interesting", .link, 6, (2026, 11, 6, 7, 0), .issue, "R20"),
        ex(42, "For the house", .link, 25, (2026, 11, 7, 9, 0), .notification, "R20"),
        ex(43, "When Sam visits", .note, nil, (2026, 11, 6, 7, 0), .issue, "R21"),
        ex(44, "When it gets cold", .link, nil, (2026, 12, 1, 7, 0), .issue, "R21",
           title: "Weeknight chili", hints: ModelHints(monthHint: 12)),
        ex(45, "Every Monday", .note, nil, (2026, 11, 9, 7, 0), .issue, "R22"),
    ]

    static func input(_ e: PlannerExample) -> PlanInput {
        PlanInput(reason: e.reason, kind: e.kind, minutes: e.minutes, title: e.title, now: e.now,
                  events: events, hints: e.hints)
    }

    static func plan(_ reason: String, kind: SaveKind = .link, minutes: Int? = nil, now: Date = PlannerTests.now,
                     hints: ModelHints? = nil, planned: [Date: Int] = [:]) -> PlanOutcome {
        ReturnPlanner.plan(PlanInput(reason: reason, kind: kind, minutes: minutes, now: now, events: events,
                                     plannedPerDay: planned, hints: hints), calendar: cal)
    }

    static func parts(_ d: Date) -> [Int] {
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: d)
        return [c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0]
    }

    // MARK: The 45 examples

    @Test(arguments: PlannerTests.examples)
    func specExample(_ e: PlannerExample) {
        let m = ReturnPlanner.plan(Self.input(e), calendar: Self.cal).moment
        #expect(Self.parts(m.start) == [e.year, e.month, e.day, e.hour, e.minute], "start \(m.explanation)")
        #expect(m.surface == e.surface)
        #expect(m.ruleId == e.rule)
        #expect(m.start >= e.now)
        #expect(m.end > m.start)
        #expect(m.explanation.count <= 60)
        #expect(!m.explanation.isEmpty)
        #expect(m.laterLabel.count <= 18)
    }

    @Test func example33WithoutRelay() {
        let m = Self.plan("Drive it next fall").moment
        #expect(Self.parts(m.start) == [2027, 9, 25, 9, 0])
        #expect(m.ruleId == "R15")
    }

    @Test func example43AsksThenGuesses() {
        let e = Self.examples[42]
        guard case .ask(let choices, let fallback) = ReturnPlanner.plan(Self.input(e), calendar: Self.cal) else {
            Issue.record("expected .ask"); return
        }
        #expect(choices == ["This weekend", "Next month", "Pick a date"])
        #expect(Self.parts(fallback.start) == [2026, 11, 6, 7, 0])
        #expect(fallback.confidence == .guess)
        #expect(fallback.surface == .issue)
    }

    @Test func example44AsksThenUsesTheModelsMonth() {
        let e = Self.examples[43]
        guard case .ask(let choices, let fallback) = ReturnPlanner.plan(Self.input(e), calendar: Self.cal) else {
            Issue.record("expected .ask"); return
        }
        #expect(choices.count == 3)
        #expect(Self.parts(fallback.start) == [2026, 12, 1, 7, 0])
        #expect(fallback.confidence == .guess)
    }

    @Test func example45OffersAReminder() {
        let e = Self.examples[44]
        guard case .offerReminder(let fallback) = ReturnPlanner.plan(Self.input(e), calendar: Self.cal) else {
            Issue.record("expected .offerReminder"); return
        }
        #expect(Self.parts(fallback.start) == [2026, 11, 9, 7, 0])
        #expect(fallback.ruleId == "R22")
    }

    // MARK: Capture line and windows

    @Test func captureLines() {
        let one = ReturnPlanner.plan(Self.input(Self.examples[0]), calendar: Self.cal).moment
        #expect(one.explanation == "Back at 9:48, before Quarterly planning")
        #expect(one.laterLabel == "After planning")
        #expect(one.anchorEventId == "planning")
        #expect(Self.parts(one.end) == [2026, 11, 5, 10, 0])

        #expect(ReturnPlanner.plan(Self.input(Self.examples[3]), calendar: Self.cal).moment.explanation == "Back at dinner tonight")
        #expect(ReturnPlanner.plan(Self.input(Self.examples[13]), calendar: Self.cal).moment.explanation == "Comes back Saturday morning")
    }

    @Test func windows() {
        let seven = Self.plan("7pm").moment
        #expect(Self.parts(seven.end) == [2026, 11, 4, 21, 0])      // 3 hours or 9 PM, whichever sooner
        let hour = Self.plan("In an hour").moment
        #expect(Self.parts(hour.end) == [2026, 11, 4, 18, 0])
        let issue = Self.plan("Tomorrow").moment
        #expect(Self.parts(issue.end) == [2026, 11, 5, 23, 59])
    }

    // MARK: Guards

    @Test(arguments: ["This morning", "Register by Nov 5", "Call about Nov 4", "At lunch", "Nov 2", "Today",
                      "Before Thanksgiving", "Gift for Nov 6", "In 5 minutes", "at 1", "Every day"])
    func neverInThePast(_ reason: String) {
        let m = Self.plan(reason).moment
        #expect(m.start >= Self.now)
        #expect(m.end > m.start)
    }

    @Test func deadlineTooCloseComesBackToday() {
        // Two days before and the day before have both passed: this afternoon, not after the deadline.
        let m = Self.plan("Register by Nov 5").moment
        #expect(Self.parts(m.start) == [2026, 11, 4, 15, 30])
    }

    @Test func quietHours() {
        let eight = Date(timeIntervalSince1970: 1_793_818_800 + 6 * 3600)   // Wed 8:00 PM
        let rel = Self.plan("In 2 hours", now: eight).moment
        #expect(Self.parts(rel.start) == [2026, 11, 5, 7, 0])
        #expect(rel.surface == .issue)
        // A time you set yourself may land in quiet hours.
        let own = Self.plan("10pm", now: eight).moment
        #expect(Self.parts(own.start) == [2026, 11, 4, 22, 0])
        #expect(own.ruleId == "R1")
        // Without am/pm, the reading outside quiet hours.
        let nine = Self.plan("at 9").moment
        #expect(Self.parts(nine.start) == [2026, 11, 5, 9, 0])
    }

    @Test func eighteenMonthCap() {
        let m = Self.plan("In 3 years").moment
        let cap = Self.cal.date(byAdding: .month, value: 18, to: Self.now)!
        #expect(m.start <= cap)
        #expect(Self.parts(m.start) == [2028, 5, 4, 7, 0])
        #expect(m.surface == .issue)
    }

    @Test func lightestDay() {
        let c = Self.cal
        let planned: [Date: Int] = [
            c.startOfDay(for: Self.at(2026, 11, 6)): 4,   // full
            c.startOfDay(for: Self.at(2026, 11, 7)): 2,
        ]
        let m = Self.plan("", minutes: 6, planned: planned).moment
        #expect(Self.parts(m.start) == [2026, 11, 8, 8, 0])
    }

    // MARK: Later

    @Test(arguments: [
        (LaterChoice.tonight, [2026, 11, 4, 19, 30]),
        (LaterChoice.tomorrowMorning, [2026, 11, 5, 7, 0]),
        (LaterChoice.thisWeekend, [2026, 11, 7, 9, 0]),
        (LaterChoice.nextWeek, [2026, 11, 9, 7, 0]),
        (LaterChoice.youChoose, [2026, 11, 6, 7, 0]),
    ])
    func laterChoices(_ choice: LaterChoice, _ expected: [Int]) {
        let input = PlanInput(reason: "Read before we plan next quarter", kind: .link, minutes: 6, now: Self.now,
                              events: Self.events)
        let m = ReturnPlanner.later(choice, input: input, calendar: Self.cal)
        #expect(Self.parts(m.start) == expected)
        #expect(m.start >= Self.now)
    }

    @Test func laterCoversEveryChoice() {
        #expect(LaterChoice.allCases.count == 5)
    }

    // MARK: needsModel

    @Test(arguments: [
        ("Interesting", true), ("For the house", true), ("When it gets cold", true), ("Read on the plane", true),
        ("", false), ("   ", false), ("Tomorrow", false), ("Someday", false), ("Next quarter", false),
        ("7pm", false), ("This weekend", false), ("Every Monday", false),
    ])
    func needsModel(_ reason: String, _ expected: Bool) {
        #expect(ReturnPlanner.needsModel(reason) == expected)
    }
}
