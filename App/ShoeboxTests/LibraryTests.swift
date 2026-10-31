import XCTest
@testable import Shoebox

final class LibraryTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    // Friday, October 30, 2026, 4 PM Eastern.
    private var now: Date { date(2026, 10, 30, 16) }
    private var rules: TodayRules { TodayRules(calendar: cal) }
    private var actions: SaveActions { SaveActions(calendar: cal) }
    private var planner: LaterPlanner { LaterPlanner(calendar: cal) }

    func testLibraryHoldsEverythingNotPutAway() {
        let onToday = Save(title: "On today", createdAt: date(2026, 10, 1))
        let waiting = Save(title: "Waiting", status: .away, returnDate: date(2026, 11, 2, 8), createdAt: date(2026, 10, 2))
        let seen = Save(title: "Seen", createdAt: date(2026, 10, 3))
        seen.seenOn = now
        let done = Save(title: "Done", status: .kept, createdAt: date(2026, 10, 4))
        let gone = Save(title: "Gone", createdAt: date(2026, 10, 5))
        gone.deletedAt = now
        let titles = rules.library([done, waiting, gone, seen, onToday], now: now).map(\.title)
        XCTAssertEqual(titles, ["On today", "Seen", "Waiting"])
    }

    func testPutAwayLeavesTheLibraryAndBringBackReturnsIt() {
        let s = Save(title: "A", createdAt: date(2026, 10, 1))
        actions.done(s, now: now)
        XCTAssertTrue(rules.library([s], now: now).isEmpty)
        XCTAssertEqual(rules.kept([s]).count, 1)
        actions.bringBack(s, now: now)
        XCTAssertEqual(rules.library([s], now: now).count, 1)
    }

    func testSeenTodayComesBackTomorrowMorning() {
        let s = Save(title: "A")
        s.seenOn = now
        XCTAssertEqual(rules.comesBack(s, now: now), date(2026, 10, 31, 8))
        XCTAssertNil(rules.comesBack(Save(title: "B"), now: now))
    }

    func testNextUsesYourWhyElseTomorrow() {
        let plain = Save(title: "A")
        XCTAssertEqual(actions.next(plain, planner: planner, now: now), "Back tomorrow")
        XCTAssertFalse(rules.isOnToday(plain, now: now))
        let dated = Save(title: "B", eventDate: date(2026, 11, 20))
        XCTAssertEqual(actions.next(dated, planner: planner, now: now), "Back before the date")
        XCTAssertEqual(dated.status, .away)
    }

    func testDeleteIsSoftAndUndoRestores() {
        let s = Save(title: "A")
        let snapshot = SaveSnapshot(s)
        actions.letGo(s, now: now)
        XCTAssertNotNil(s.deletedAt)
        XCTAssertTrue(rules.library([s], now: now).isEmpty)
        snapshot.restore(s)
        XCTAssertNil(s.deletedAt)
        XCTAssertEqual(rules.library([s], now: now).count, 1)
    }
}
