import XCTest
@testable import Shoebox

/// "Just put away": your own put-aways from today and the two days before, newest first, and Undo puts it back.
final class PutAwayLogTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // Saturday, November 7, 2026, 9 AM Eastern.
    private var now: Date { date(2026, 11, 7, 9) }

    private func freshLog() -> PutAwayLog {
        let name = "putaway-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return PutAwayLog(defaults: d, calendar: cal)
    }

    private var actions: SaveActions { SaveActions(calendar: cal) }

    func testPuttingAwayRecordsTheTime() {
        let log = freshLog(), s = Save(title: "A")
        actions.done(s, now: now, log: log)
        XCTAssertEqual(log.at(s.id), now)
        XCTAssertEqual(log.recent([s], now: now).map(\.id), [s.id])
        XCTAssertEqual(log.line(s, now: now), "Put away today")
    }

    func testTodayAndTheTwoDaysBeforeCountNewestFirst() {
        let log = freshLog()
        let thu = Save(title: "Thursday"), fri = Save(title: "Friday"), sat = Save(title: "Saturday"), wed = Save(title: "Wednesday")
        actions.done(wed, now: date(2026, 11, 4, 23, 59), log: log)
        actions.done(thu, now: date(2026, 11, 5, 0, 1), log: log)
        actions.done(fri, now: date(2026, 11, 6, 18), log: log)
        actions.done(sat, now: date(2026, 11, 7, 8), log: log)
        XCTAssertEqual(log.recent([wed, thu, fri, sat], now: now).map(\.title), ["Saturday", "Friday", "Thursday"])
        XCTAssertEqual(log.line(fri, now: now), "Put away yesterday")
        XCTAssertEqual(log.line(thu, now: now), "Put away Thursday")
    }

    func testOnlyPostsStillPutAwayAndNotDeletedShow() {
        let log = freshLog()
        let back = Save(title: "Back"), gone = Save(title: "Gone"), kept = Save(title: "Kept")
        for s in [back, gone, kept] { actions.done(s, now: now, log: log) }
        actions.bringBack(back, now: now, log: log)
        actions.letGo(gone, now: now)
        XCTAssertNil(log.at(back.id))
        XCTAssertEqual(log.recent([back, gone, kept], now: now).map(\.title), ["Kept"])
    }

    func testPastEventsKeptOnTheirOwnAreNotListed() {
        let log = freshLog()
        let s = Save(title: "Concert", eventDate: date(2026, 11, 6, 17))
        TodayRules(calendar: cal).retirePast([s], now: now)
        XCTAssertEqual(s.status, .kept)
        XCTAssertTrue(log.recent([s], now: now).isEmpty)
    }

    func testUndoPutsTheListBackAsItWas() {
        let log = freshLog(), s = Save(title: "A")
        let before = SaveSnapshot(s, log: log)
        actions.done(s, now: now, log: log)
        before.restore(s)
        XCTAssertEqual(s.status, .today)
        XCTAssertNil(log.at(s.id))

        actions.done(s, now: now, log: log)
        let kept = SaveSnapshot(s, log: log)
        actions.bringBack(s, now: now, log: log)
        kept.restore(s)
        XCTAssertEqual(s.status, .kept)
        XCTAssertEqual(log.at(s.id), now)
    }

    func testOldEntriesAreDroppedWhenOneIsWritten() {
        let log = freshLog(), old = Save(title: "Old"), new = Save(title: "New")
        log.set(old.id, date(2026, 10, 20))
        log.set(new.id, now)
        XCTAssertNil(log.at(old.id))
        XCTAssertEqual(log.at(new.id), now)
    }
}
