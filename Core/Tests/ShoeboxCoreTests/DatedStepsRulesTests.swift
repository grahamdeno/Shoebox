import Foundation
import Testing
@testable import ShoeboxCore

struct DatedStepsRulesTests {
    static var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }
    // Wed Nov 4 2026, 2:00 PM New York.
    static let now = Date(timeIntervalSince1970: 1_793_818_800)

    func day(_ m: Int, _ d: Int) -> Date { Self.cal.date(from: DateComponents(year: 2026, month: m, day: d))! }
    func parts(_ d: Date) -> [Int] { let c = Self.cal.dateComponents([.month, .day, .hour, .minute], from: d); return [c.month!, c.day!, c.hour!, c.minute!] }

    @Test func todoHasThreeSteps() throws {
        let target = day(11, 20)   // Friday
        let a = try #require(DatedSteps.next(target: target, kind: .todo, now: Self.now, isNew: true, calendar: Self.cal))
        #expect(parts(a.start) == [11, 15, 8, 0])          // Sunday: weekend Issue, 5 days before
        #expect(a.surface == .issue && a.laterLabel == "Evening before")
        let b = try #require(DatedSteps.next(target: target, kind: .todo, now: a.start, calendar: Self.cal))
        #expect(parts(b.start) == [11, 19, 18, 30])         // evening before, home evening + 30 min
        #expect(b.surface == .notification && b.laterLabel == "Day of")
        let c = try #require(DatedSteps.next(target: target, kind: .todo, now: b.start, calendar: Self.cal))
        #expect(parts(c.start) == [11, 20, 7, 0])           // day of, weekday Issue
        #expect(DatedSteps.next(target: target, kind: .todo, now: c.start, calendar: Self.cal) == nil)
    }

    @Test func happeningIsEveningBeforeOnly() throws {
        let a = try #require(DatedSteps.next(target: day(11, 11), kind: .happening, now: Self.now, isNew: true, calendar: Self.cal))
        #expect(parts(a.start) == [11, 10, 18, 30])
        #expect(DatedSteps.next(target: day(11, 11), kind: .happening, now: a.start, calendar: Self.cal) == nil)
    }

    @Test func todoUnderFiveDaysStartsAtNextIssue() throws {
        let a = try #require(DatedSteps.next(target: day(11, 7), kind: .todo, now: Self.now, isNew: true, calendar: Self.cal))
        #expect(parts(a.start) == [11, 5, 7, 0])            // Thursday's Issue
        #expect(a.ruleId == "step-first")
        let b = try #require(DatedSteps.next(target: day(11, 7), kind: .todo, now: a.start, calendar: Self.cal))
        #expect(parts(b.start) == [11, 6, 18, 30])
    }

    @Test func tomorrowTodoGoesStraightToEvening() throws {
        let a = try #require(DatedSteps.next(target: day(11, 5), kind: .todo, now: Self.now, isNew: true, calendar: Self.cal))
        #expect(parts(a.start) == [11, 4, 18, 30])
    }

    @Test func pastTargetHasNoSteps() {
        #expect(DatedSteps.next(target: day(11, 1), kind: .todo, now: Self.now, calendar: Self.cal) == nil)
    }
}
