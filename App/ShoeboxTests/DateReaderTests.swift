import XCTest
@testable import Shoebox

final class DateReaderTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // Monday, October 26, 2026.
    private var kept: Date { date(2026, 10, 26, 9) }

    func testDanceNamesItsDayAndStartTime() {
        let text = "The Halloween Dance runs 4:00 to 6:00 in the gym on October 30, with dismissal for pickup at 5:45. Tickets are $5."
        let r = DateReader.read(text, created: kept, calendar: cal)
        XCTAssertEqual(r?.event, date(2026, 10, 30, 16))
        XCTAssertEqual(r?.hasTime, true)
    }

    func testDeadlineIsKeptAsAnotherDate() {
        let text = "Spring Fling is Nov 7. Permission forms due Nov 3."
        let r = DateReader.read(text, created: kept, calendar: cal)
        XCTAssertEqual(r?.event, date(2026, 11, 7))
        XCTAssertEqual(r?.others, [date(2026, 11, 3)])
    }

    func testOnlyADeadlineBecomesTheDate() {
        let r = DateReader.read("Forms due Nov 3", created: kept, calendar: cal)
        XCTAssertEqual(r?.event, date(2026, 11, 3))
        XCTAssertEqual(r?.hasTime, false)
    }

    func testADayJustPassedIsHistory() {
        XCTAssertNil(DateReader.read("October 30 dance", created: date(2026, 10, 31, 9), calendar: cal))
    }

    func testYearlessDateFarBackMeansNextYear() {
        let r = DateReader.read("Registration opens March 3", created: date(2026, 10, 31, 9), calendar: cal)
        XCTAssertEqual(r?.event, date(2027, 3, 3))
    }

    func testWeekdayWithinTwoWeeks() {
        let r = DateReader.read("Dinner Friday at 7pm", created: kept, calendar: cal)
        XCTAssertEqual(r?.event, date(2026, 10, 30, 19))
    }

    func testNumericDate() {
        let r = DateReader.read("Conference 11/12", created: kept, calendar: cal)
        XCTAssertEqual(r?.event, date(2026, 11, 12))
    }

    func testLinkDigitsAreNotDates() {
        XCTAssertNil(DateReader.read("https://example.com/2026/10/30/post-12/5", created: kept, calendar: cal))
    }

    func testTimeFromTheNextSentence() {
        let r = DateReader.read("Concert is Nov 14. Doors open at 6 PM.", created: kept, calendar: cal)
        XCTAssertEqual(r?.event, date(2026, 11, 14, 18))
    }

    func testNoDateNoReading() {
        XCTAssertNil(DateReader.read("Read this someday", created: kept, calendar: cal))
    }

    func testApplySetsTheSaveFields() {
        let s = Save(title: "Halloween Dance in the gym on October 30", snippet: "Runs 4:00 to 6:00", createdAt: kept)
        XCTAssertTrue(DateReader.apply(to: s, calendar: cal))
        XCTAssertEqual(s.eventDate, date(2026, 10, 30, 16))
        XCTAssertTrue(s.eventHasTime)
    }

    func testPageBodyIsNotReadForLinks() {
        let s = Save(title: "An article", body: "Posted October 28. Updated Nov 2.", kind: .link, urlString: "https://example.com/a", createdAt: kept)
        XCTAssertFalse(DateReader.apply(to: s, calendar: cal))
        XCTAssertNil(s.eventDate)
    }

    func testPastEventsMoveToKeptNotDeleted() {
        let rules = TodayRules(calendar: cal)
        let past = Save(title: "Dance", status: .today, eventDate: date(2026, 10, 30, 16), createdAt: kept)
        let upcoming = Save(title: "Fling", status: .today, eventDate: date(2026, 11, 7), createdAt: kept)
        let now = date(2026, 10, 31, 8)
        XCTAssertFalse(rules.isOnToday(past, now: now))
        XCTAssertEqual(rules.retirePast([past, upcoming], now: now), 1)
        XCTAssertEqual(past.status, .kept)
        XCTAssertNil(past.deletedAt)
        XCTAssertEqual(upcoming.status, .today)
    }

    func testNearestEventComesFirst() {
        let rules = TodayRules(calendar: cal)
        let far = Save(title: "Far", status: .away, returnDate: date(2026, 10, 27, 8), eventDate: date(2026, 11, 20), createdAt: kept)
        let near = Save(title: "Near", status: .away, returnDate: date(2026, 10, 28, 8), eventDate: date(2026, 10, 30), createdAt: kept)
        let order = rules.queue([far, near], now: date(2026, 10, 29, 9)).map(\.title)
        XCTAssertEqual(order, ["Near", "Far"])
    }

    // MARK: Review fixes

    func testRangeUsesTheEndsAmPmAndTakesTheStart() {
        XCTAssertEqual(DateReader.read("Dance Oct 30, 6-8pm", created: kept, calendar: cal)?.event, date(2026, 10, 30, 18))
        XCTAssertEqual(DateReader.read("Open house Oct 30, 7:00 to 9:00 pm", created: kept, calendar: cal)?.event, date(2026, 10, 30, 19))
        XCTAssertEqual(DateReader.read("Brunch Oct 30, 10-12pm", created: kept, calendar: cal)?.event, date(2026, 10, 30, 10))
    }

    func testBareSevenToElevenGivesNoTime() {
        let r = DateReader.read("Meeting October 31, 7:00 to 9:00", created: kept, calendar: cal)
        XCTAssertEqual(r?.event, date(2026, 10, 31))
        XCTAssertEqual(r?.hasTime, false)
    }

    func testRecentPastDateIsHistory() {
        XCTAssertNil(DateReader.read("Recap of the Oct 12 board meeting", created: date(2026, 10, 31, 9), calendar: cal))
    }

    func testFractionsAndRatingsAreNotDates() {
        XCTAssertNil(DateReader.read("Use 1/2 cup sugar", created: kept, calendar: cal))
        XCTAssertNil(DateReader.read("Rated 4/5 by readers", created: kept, calendar: cal))
        XCTAssertNil(DateReader.read("Mix 3/4 of the flour", created: kept, calendar: cal))
        XCTAssertEqual(DateReader.read("Forms due 1/2", created: date(2026, 12, 20, 9), calendar: cal)?.event, date(2027, 1, 2))
        XCTAssertEqual(DateReader.read("PTA meeting 11/12 in the gym", created: kept, calendar: cal)?.event, date(2026, 11, 12))
    }

    func testWeekdayPhrasesThatNameNoComingDay() {
        XCTAssertNil(DateReader.read("Black Friday deals", created: kept, calendar: cal))
        XCTAssertNil(DateReader.read("We talked last Monday", created: kept, calendar: cal))
        XCTAssertNil(DateReader.read("Yoga every Tuesday", created: kept, calendar: cal))
    }

    func testWeekdayOnThatWeekdayMeansToday() {
        let friday = date(2026, 10, 30, 9)
        XCTAssertEqual(DateReader.read("Dinner Friday", created: friday, calendar: cal)?.event, date(2026, 10, 30))
        XCTAssertEqual(DateReader.read("Dinner next Friday", created: friday, calendar: cal)?.event, date(2026, 11, 6))
    }

    func testYourReasonIsReadForWrittenDatesOnly() {
        let a = Save(title: "An article", kind: .link, urlString: "https://example.com/a", createdAt: kept)
        a.note = "Read this Monday"
        XCTAssertFalse(DateReader.apply(to: a, calendar: cal))
        let b = Save(title: "An article", kind: .link, urlString: "https://example.com/b", createdAt: kept)
        b.note = "before Nov 3"
        XCTAssertTrue(DateReader.apply(to: b, calendar: cal))
        XCTAssertEqual(b.eventDate, date(2026, 11, 3))
    }

    func testPageTextOfVideosAndFilesIsNotRead() {
        let s = Save(title: "A talk", body: "Recorded November 9.", kind: .video, urlString: "https://example.com/v", createdAt: kept)
        XCTAssertFalse(DateReader.apply(to: s, calendar: cal))
    }

    func testOldSaveIsReadAsOfToday() {
        let s = Save(title: "Fair on October 12", kind: .note, createdAt: date(2026, 10, 1, 9))
        XCTAssertFalse(DateReader.apply(to: s, calendar: cal, asOf: date(2026, 10, 31, 9)))
        XCTAssertNil(s.eventDate)
    }

    func testBringBackClearsAPastDate() {
        let now = date(2026, 10, 31, 9)
        let s = Save(title: "Dance", status: .kept, eventDate: date(2026, 10, 30, 16), createdAt: kept)
        SaveActions().bringBack(s, now: now)
        XCTAssertNil(s.eventDate)
        XCTAssertEqual(s.status, .today)
        XCTAssertEqual(TodayRules(calendar: cal).retirePast([s], now: now), 0)
    }
}
