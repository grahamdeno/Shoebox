import XCTest
@testable import Shoebox

final class RulesTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // Friday, October 30, 2026, 4 PM Eastern.
    private var now: Date { date(2026, 10, 30, 16) }

    private var rules: TodayRules { TodayRules(calendar: cal) }
    private var actions: SaveActions { SaveActions(calendar: cal) }

    func testNewSaveIsOnToday() {
        let s = Save(title: "A")
        XCTAssertTrue(rules.isOnToday(s, now: now))
    }

    func testPassHidesUntilTomorrow() {
        let s = Save(title: "A")
        actions.pass(s, now: now)
        XCTAssertFalse(rules.isOnToday(s, now: now))
        XCTAssertFalse(rules.isOnToday(s, now: date(2026, 10, 30, 23, 59)))
        XCTAssertTrue(rules.isOnToday(s, now: date(2026, 10, 31, 8)))
    }

    func testPassNeverQuiets() {
        let s = Save(title: "A")
        for day in 0..<10 {
            let t = date(2026, 10, 30 + 0, 9).addingTimeInterval(Double(day) * 86_400)
            XCTAssertTrue(rules.isOnToday(s, now: t), "day \(day)")
            actions.pass(s, now: t)
        }
    }

    func testDoneLeavesToday() {
        let s = Save(title: "A")
        actions.done(s, now: now)
        XCTAssertEqual(s.status, .kept)
        XCTAssertFalse(rules.isOnToday(s, now: date(2026, 11, 5)))
        XCTAssertEqual(rules.kept([s]).count, 1)
    }

    func testLaterWaitsUntilDate() {
        let s = Save(title: "A")
        let back = date(2026, 11, 7, 9)
        actions.later(s, until: back, now: now)
        XCTAssertFalse(rules.isOnToday(s, now: date(2026, 11, 6, 12)))
        XCTAssertTrue(rules.isOnToday(s, now: date(2026, 11, 7, 9, 1)))
        XCTAssertEqual(rules.away([s], now: now).count, 1)
    }

    func testLetGoRemovesSoftly() {
        let s = Save(title: "A")
        actions.letGo(s, now: now)
        XCTAssertNotNil(s.deletedAt)
        XCTAssertFalse(rules.isOnToday(s, now: now))
        XCTAssertTrue(rules.away([s], now: now).isEmpty)
        XCTAssertTrue(rules.kept([s]).isEmpty)
    }

    func testUndoRestoresEveryChange() {
        let s = Save(title: "A")
        let snap = SaveSnapshot(s)
        actions.later(s, until: date(2026, 11, 7, 9), now: now)
        snap.restore(s)
        XCTAssertEqual(s.status, .today)
        XCTAssertNil(s.returnDate)
        XCTAssertTrue(rules.isOnToday(s, now: now))
    }

    func testBringBackPutsItOnToday() {
        let s = Save(title: "A", status: .away, returnDate: date(2026, 12, 1))
        actions.bringBack(s, now: now)
        XCTAssertTrue(rules.isOnToday(s, now: now))
    }

    func testDatedSaveReturnsFiveDaysOneDayAndOnTheDay() {
        let event = date(2026, 11, 12)
        XCTAssertEqual(actions.reminders(for: event), [
            date(2026, 11, 7, 8), date(2026, 11, 11, 8), date(2026, 11, 12, 8),
        ])
        let s = Save(title: "Picture day", status: .away, returnDate: date(2026, 11, 7, 8), eventDate: event)
        XCTAssertFalse(rules.isOnToday(s, now: date(2026, 11, 6, 20)))
        XCTAssertTrue(rules.isOnToday(s, now: date(2026, 11, 7, 9)))
        actions.pass(s, now: date(2026, 11, 7, 9))
        XCTAssertEqual(s.returnDate, date(2026, 11, 11, 8))
        actions.pass(s, now: date(2026, 11, 11, 9))
        XCTAssertEqual(s.returnDate, date(2026, 11, 12, 8))
        actions.pass(s, now: date(2026, 11, 12, 9))
        XCTAssertEqual(s.status, .kept)
    }

    func testQueueOrdersReturningFirstThenOldest() {
        let old = Save(title: "old", createdAt: date(2026, 10, 1))
        let newer = Save(title: "newer", createdAt: date(2026, 10, 20))
        let returning = Save(title: "returning", status: .away, returnDate: date(2026, 10, 30, 8), createdAt: date(2026, 10, 25))
        let order = rules.queue([newer, returning, old], now: now).map(\.title)
        XCTAssertEqual(order, ["returning", "old", "newer"])
    }
}

final class LaterPlannerTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private var now: Date { date(2026, 10, 30, 16) } // Friday
    private var planner: LaterPlanner { LaterPlanner(calendar: cal) }

    func testWeekendMeansSaturdayMorning() {
        let s = Save(title: "Trail", note: "Take the kids this weekend")
        XCTAssertEqual(planner.suggestion(for: s, now: now).date, date(2026, 10, 31, 9))
    }

    func testBeforeMondayMeansSundayEvening() {
        let s = Save(title: "Article", note: "Read before Monday")
        XCTAssertEqual(planner.suggestion(for: s, now: now).date, date(2026, 11, 1, 18))
    }

    func testNamedWeekdayMeansThatMorning() {
        let s = Save(title: "Retro", note: "Ask the team Tuesday")
        XCTAssertEqual(planner.suggestion(for: s, now: now).date, date(2026, 11, 3, 8))
    }

    func testEveningStaysToday() {
        let s = Save(title: "Recipe", note: "Make at dinner")
        XCTAssertEqual(planner.suggestion(for: s, now: now).date, date(2026, 10, 30, 18))
    }

    func testNoDateFallsBackToNextWeek() {
        let s = Save(title: "Cast iron", note: "")
        let result = planner.suggestion(for: s, now: now)
        XCTAssertEqual(result.date, date(2026, 11, 2, 8))
        XCTAssertEqual(result.label, "Next week" )
    }

    func testDatedSaveSuggestsNextReminder() {
        let s = Save(title: "Picture day", eventDate: date(2026, 11, 12))
        XCTAssertEqual(planner.suggestion(for: s, now: now).date, date(2026, 11, 7, 8))
    }

    func testNewSaveWithoutAWhyComesBackTomorrowMorning() {
        XCTAssertEqual(planner.firstReturn(note: "", now: now), date(2026, 10, 31, 8))
    }

    func testLabels() {
        XCTAssertEqual(planner.label(for: date(2026, 10, 31, 8), now: now), "Tomorrow")
        XCTAssertEqual(planner.label(for: date(2026, 11, 1, 8), now: now), "This weekend")
        XCTAssertEqual(planner.label(for: date(2026, 11, 3, 8), now: now), "Tuesday")
        XCTAssertEqual(planner.label(for: date(2026, 11, 12, 8), now: now), "Nov 12")
    }
}
