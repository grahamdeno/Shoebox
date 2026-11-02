import XCTest
@testable import Shoebox

final class WritingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_620_000)

    func testAutomaticLetsTheWordsDecide() {
        XCTAssertNil(ReturnChoice.auto.start(now: now))
        XCTAssertEqual(ReturnLine.text(.auto, event: nil, why: "", now: now), "Back tomorrow")
    }

    func testChoicesStartInTheMorning() throws {
        let cal = Calendar.current
        let tomorrow = try XCTUnwrap(ReturnChoice.tomorrow.start(now: now))
        XCTAssertGreaterThan(tomorrow, now)
        XCTAssertLessThan(tomorrow.timeIntervalSince(now), 2 * 86_400)
        let weekend = try XCTUnwrap(ReturnChoice.weekend.start(now: now))
        XCTAssertEqual(cal.component(.weekday, from: weekend), 7)
        let week = try XCTUnwrap(ReturnChoice.nextWeek.start(now: now))
        XCTAssertEqual(cal.component(.weekday, from: week), 2)
        let day = try XCTUnwrap(cal.date(byAdding: .day, value: 9, to: now))
        let start = try XCTUnwrap(ReturnChoice.day(day).start(now: now))
        XCTAssertEqual(cal.component(.hour, from: start), 8)
        XCTAssertEqual(cal.startOfDay(for: start), cal.startOfDay(for: day))
    }

    func testAChosenDayWaitsAndClearsAnEarlierEventDate() throws {
        let cal = Calendar.current
        let s = Save(title: "Banquet", note: "", origin: "a note", kind: .note, createdAt: now)
        s.eventDate = cal.date(byAdding: .day, value: 3, to: now)
        s.status = .today
        let day = try XCTUnwrap(cal.date(byAdding: .day, value: 10, to: now))
        ReturnChoice.day(day).apply(to: [s], now: now)
        XCTAssertEqual(s.status, .away)
        XCTAssertNotNil(s.returnDate)
        XCTAssertNil(s.eventDate)
    }

    func testAutomaticLeavesASaveAlone() {
        let s = Save(title: "Note", note: "", origin: "a note", kind: .note, createdAt: now)
        s.status = .today
        ReturnChoice.auto.apply(to: [s], now: now)
        XCTAssertEqual(s.status, .today)
    }

    func testADatedSaveSaysWhenItComesBack() throws {
        let event = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 12, to: now))
        XCTAssertTrue(ReturnLine.text(.auto, event: event, why: "", now: now).hasSuffix("· 5 days before"))
        XCTAssertTrue(ReturnLine.text(.auto, event: event, why: "", now: now).hasPrefix("Back "))
    }

    func testAReasonThatNamesATimeWins() {
        let line = ReturnLine.text(.auto, event: nil, why: "Read this weekend", now: now)
        XCTAssertEqual(line, "Back this weekend")
    }

    func testPhotoTextBecomesATitleAndDetails() throws {
        let g = try XCTUnwrap(PhotoRead.plain("HARBOR 10K\nSaturday, December 5\n7:30 AM start\nRiverfront Park"))
        XCTAssertEqual(g.words.split(separator: "\n").first, "HARBOR 10K")
        XCTAssertTrue(g.words.contains("Saturday, December 5 · 7:30 AM start · Riverfront Park"))
    }

    func testNothingReadableMeansNoSuggestion() async {
        let none = await PhotoRead.gist(from: "  \n a ")
        XCTAssertNil(none)
    }
}
