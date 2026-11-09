import XCTest
@testable import Shoebox

/// SPEC 2.9: one notification a day at the chosen time, naming the first post and how many more.
/// The scheduling is the system's; what it says and when is ours, and is checked here.
@MainActor
final class NotifierTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    // Friday, October 30, 2026, 4 PM Eastern. The notification is at 8 AM (480 minutes).
    private var now: Date { date(2026, 10, 30, 16) }

    func testNothingKeptMeansNoNotifications() {
        XCTAssertTrue(Notifier.plan([], now: now, minute: 480, perDay: Prefs.noLimit, calendar: cal).isEmpty)
    }

    func testTodaysTimeHasGoneSoItStartsTomorrow() {
        let s = Save(title: "Call the dentist", createdAt: now - 3_600)
        let plan = Notifier.plan([s], now: now, minute: 480, perDay: Prefs.noLimit, calendar: cal)
        XCTAssertEqual(plan.first?.at, date(2026, 10, 31, 8))
        XCTAssertLessThanOrEqual(plan.count, 7)
    }

    func testOnePostIsNamed() {
        let s = Save(title: "Call the dentist", createdAt: now - 3_600)
        let first = Notifier.plan([s], now: now, minute: 480, perDay: Prefs.noLimit, calendar: cal).first
        XCTAssertEqual(first?.title, "1 came out of the box")
        XCTAssertEqual(first?.body, "Call the dentist")
    }

    func testSeveralNameTheFirstAndCountTheRest() {
        let a = Save(title: "Call the dentist", createdAt: now - 7_200)
        let b = Save(title: "Field trip form", createdAt: now - 3_600)
        let c = Save(title: "Cast iron care", createdAt: now - 1_800)
        let first = Notifier.plan([a, b, c], now: now, minute: 480, perDay: Prefs.noLimit, calendar: cal).first
        XCTAssertEqual(first?.title, "3 came out of the box")
        XCTAssertEqual(first?.body, "Call the dentist, plus 2 more.")
    }

    func testTheDailyLimitHoldsTheCount() {
        let posts = (0..<8).map { Save(title: "Post \($0)", createdAt: now - Double(8 - $0) * 600) }
        let first = Notifier.plan(posts, now: now, minute: 480, perDay: 5, calendar: cal).first
        XCTAssertEqual(first?.title, "5 came out of the box")
    }

    func testAPostAwayUntilTuesdayIsInTuesdaysNotification() {
        let s = Save(title: "Renew the car tag", status: .away, returnDate: date(2026, 11, 3, 8), createdAt: now - 86_400)
        let plan = Notifier.plan([s], now: now, minute: 480, perDay: Prefs.noLimit, calendar: cal)
        XCTAssertEqual(plan.first?.at, date(2026, 11, 3, 8))
        XCTAssertEqual(plan.first?.body, "Renew the car tag")
    }
}
