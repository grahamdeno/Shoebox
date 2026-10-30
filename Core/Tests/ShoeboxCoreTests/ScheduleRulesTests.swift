import Foundation
import Testing
@testable import ShoeboxCore

/// New York time, Wednesday November 4, 2026: the spec's example week.
enum RulesTestClock {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    /// November 2026 at a local clock time.
    static func nov(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }
}

struct QuietRulesTests {
    let cal = RulesTestClock.calendar
    func nov(_ d: Int, _ h: Int, _ m: Int = 0) -> Date { RulesTestClock.nov(d, h, m) }

    @Test func notificationWindowIsThreeHoursOrNinePM() {
        #expect(QuietRule.windowEnd(surface: .notification, deliveredAt: nov(4, 14), anchorStart: nil, calendar: cal) == nov(4, 17))
        #expect(QuietRule.windowEnd(surface: .notification, deliveredAt: nov(4, 19), anchorStart: nil, calendar: cal) == nov(4, 21))
        // A time you set yourself inside quiet hours keeps its 3 hours.
        #expect(QuietRule.windowEnd(surface: .notification, deliveredAt: nov(4, 21, 30), anchorStart: nil, calendar: cal) == nov(5, 0, 30))
    }

    @Test func issueAndLiveActivityWindows() {
        #expect(QuietRule.windowEnd(surface: .issue, deliveredAt: nov(4, 7), anchorStart: nil, calendar: cal) == nov(4, 23, 59))
        #expect(QuietRule.windowEnd(surface: .liveActivity, deliveredAt: nov(5, 9, 48), anchorStart: nov(5, 10), calendar: cal) == nov(5, 10))
        #expect(QuietRule.windowEnd(surface: .liveActivity, deliveredAt: nov(5, 9, 48), anchorStart: nil, calendar: cal) == nov(5, 12, 48))
    }

    @Test func twoPassesThenQuiet() {
        #expect(QuietRule.passesToQuiet == 2)
        #expect(QuietRule.afterPass(passes: 1) == .replan)
        #expect(QuietRule.afterPass(passes: 2) == .quiet)
        #expect(QuietRule.afterPass(passes: 3) == .quiet)
    }

    @Test func schoolInfoGoesQuietAfterOnePass() {
        #expect(QuietRule.afterPass(passes: 1, isSchoolInfo: true) == .quiet)
        #expect(QuietRule.afterPass(passes: 1, isSchoolInfo: false) == .replan)
    }

    @Test func theThirdLaterAsks() {
        #expect(!QuietRule.laterNeedsQuestion(laters: 1))
        #expect(!QuietRule.laterNeedsQuestion(laters: 2))
        #expect(QuietRule.laterNeedsQuestion(laters: 3))
    }
}

struct DailyIssueRulesTests {
    let cal = RulesTestClock.calendar
    func line(_ reason: String, _ title: String = "A title", school: Bool = false) -> DailyIssue.Line {
        DailyIssue.Line(saveId: UUID(), reason: reason, title: title, isSchool: school)
    }

    @Test func upToThreeSavesAndTwoSchoolPosts() {
        let saves = (1...5).map { line("Save \($0)") }
        let school = (1...3).map { line("Post \($0)", school: true) }
        let c = DailyIssue.compose(saves: saves, school: school)
        #expect(c.lines.map(\.reason) == ["Save 1", "Save 2", "Save 3", "Post 1", "Post 2"])
        #expect(c.overflow == [saves[3].saveId, saves[4].saveId, school[2].saveId])
        #expect(c.cover == "Save 1")
        #expect(c.more == "and 4 more")
    }

    @Test func aQuietMorningIsNeverPadded() {
        let empty = DailyIssue.compose(saves: [], school: [])
        #expect(empty.lines.isEmpty)
        #expect(empty.cover == "")
        #expect(empty.more == nil)
        let single = DailyIssue.compose(saves: [line("", "Sourdough starter guide")], school: [])
        #expect(single.lines.count == 1)
        #expect(single.cover == "Sourdough starter guide")
        #expect(single.more == nil)
    }

    @Test func aSaveListedTwiceIsUsedOnce() {
        let a = line("For the house")
        let c = DailyIssue.compose(saves: [a, a, line("Next week")], school: [])
        #expect(c.lines.count == 2)
        #expect(c.more == "and 1 more")
        #expect(c.overflow.isEmpty)
    }

    @Test func issueTimeIsSevenOnWeekdaysAndEightOnWeekends() {
        #expect(DailyIssue.time(on: RulesTestClock.nov(4, 14), calendar: cal) == RulesTestClock.nov(4, 7))
        #expect(DailyIssue.time(on: RulesTestClock.nov(7, 14), calendar: cal) == RulesTestClock.nov(7, 8))
        #expect(DailyIssue.time(on: RulesTestClock.nov(8, 1), calendar: cal) == RulesTestClock.nov(8, 8))
        #expect(DailyIssue.time(on: RulesTestClock.nov(9, 23), weekday: (6, 30), calendar: cal) == RulesTestClock.nov(9, 6, 30))
    }
}

struct DailyBudgetRulesTests {
    let cal = RulesTestClock.calendar
    func nov(_ d: Int, _ h: Int, _ m: Int = 0) -> Date { RulesTestClock.nov(d, h, m) }
    func note(_ d: Date) -> DailyBudget.Slot { DailyBudget.Slot(start: d, anchored: false, surface: .notification) }

    @Test func anchoredMomentsAlwaysKeep() {
        let full = [DailyBudget.Slot(start: nov(5, 7), anchored: false, surface: .issue), note(nov(5, 9)), note(nov(5, 12)), note(nov(5, 18))]
        let anchored = DailyBudget.Slot(start: nov(5, 9, 48), anchored: true, surface: .liveActivity)
        #expect(DailyBudget.place(anchored, existing: full, issueTime: nov(5, 7), now: nov(4, 14), calendar: cal) == .keep)
    }

    @Test func aFreeDayKeepsAndIssueLinesKeep() {
        #expect(DailyBudget.place(note(nov(4, 19, 30)), existing: [note(nov(4, 15))], issueTime: nov(4, 7), now: nov(4, 14), calendar: cal) == .keep)
        let line = DailyBudget.Slot(start: nov(5, 7), anchored: false, surface: .issue)
        #expect(DailyBudget.place(line, existing: [note(nov(5, 7, 30))], issueTime: nov(5, 7), now: nov(4, 14), calendar: cal) == .keep)
    }

    @Test func tooCloseJoinsTheIssueWhenItCanStillMakeIt() {
        let existing = [note(nov(4, 15))]
        #expect(DailyBudget.place(note(nov(4, 16)), existing: existing, issueTime: nov(4, 7), now: nov(4, 6), calendar: cal) == .joinIssue)
        // Planned on Wednesday for Saturday: Saturday's Issue is still ahead.
        let sat = [note(nov(7, 9))]
        #expect(DailyBudget.place(note(nov(7, 10)), existing: sat, issueTime: nov(7, 8), now: nov(4, 14), calendar: cal) == .joinIssue)
    }

    @Test func tooCloseAfterTheIssueMovesToTheSameTimeTomorrow() {
        let existing = [note(nov(4, 15))]
        #expect(DailyBudget.place(note(nov(4, 16)), existing: existing, issueTime: nov(4, 7), now: nov(4, 14), calendar: cal) == .move(nov(5, 16)))
    }

    @Test func anchoredMomentsDontPushOthersAwayButDoCount() {
        let anchored = DailyBudget.Slot(start: nov(4, 15, 30), anchored: true, surface: .liveActivity)
        #expect(DailyBudget.place(note(nov(4, 16)), existing: [anchored], issueTime: nov(4, 7), now: nov(4, 14), calendar: cal) == .keep)
        let full = [DailyBudget.Slot(start: nov(4, 7), anchored: false, surface: .issue), note(nov(4, 10)), note(nov(4, 13)), anchored]
        #expect(DailyBudget.place(note(nov(4, 19, 30)), existing: full, issueTime: nov(4, 7), now: nov(4, 14), calendar: cal) == .move(nov(5, 19, 30)))
    }

    @Test func overFourInADayMoves() {
        let existing = [DailyBudget.Slot(start: nov(4, 7), anchored: false, surface: .issue), note(nov(4, 10)), note(nov(4, 13)), note(nov(4, 19, 30))]
        #expect(DailyBudget.place(note(nov(4, 16, 30)), existing: existing, issueTime: nov(4, 7), now: nov(4, 14), calendar: cal) == .move(nov(5, 16, 30)))
    }

    @Test func noRoomForTwoDaysGoesToTheNextIssue() {
        let existing = [note(nov(4, 16)), note(nov(5, 16)), note(nov(6, 16))]
        #expect(DailyBudget.place(note(nov(4, 16, 30)), existing: existing, issueTime: nov(4, 7), now: nov(4, 14), calendar: cal) == .move(nov(5, 7)))
        // A custom Issue time is used when given.
        let custom = DailyBudget.place(note(nov(4, 16, 30)), existing: existing, issueTime: nov(4, 7), now: nov(4, 14), calendar: cal,
                                       issueOn: { DailyIssue.time(on: $0, weekday: (6, 30), calendar: RulesTestClock.calendar) })
        #expect(custom == .move(nov(5, 6, 30)))
    }
}
