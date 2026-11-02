import Foundation
import Testing
@testable import ShoeboxCore

struct EmailCalendarTests {
    static var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }
    static let received = Date(timeIntervalSince1970: 1_793_595_660)   // Mon Nov 2 2026, just after midnight

    static func newsletter() throws -> String {
        let url = try #require(Bundle.module.url(forResource: "newsletter-27-dates", withExtension: "txt", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func day(_ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: m, day: d))! }

    @Test func findsEveryDatedLine() throws {
        let items = EmailCalendar.items(in: try Self.newsletter(), received: Self.received, calendar: Self.cal)
        #expect(items.count == 27)
        #expect(items.first?.day == Self.day(11, 2))
        #expect(items.first?.section == "ALL GRADES")
    }

    @Test func keepsOnlyWhatIsAboutYourSon() throws {
        let items = EmailCalendar.items(in: try Self.newsletter(), received: Self.received, calendar: Self.cal)
        let profile = EmailCalendar.Profile("Gunner, 8th grade: cross country, band (trumpet), soccer, lacrosse")
        #expect(profile.grades == [8])
        #expect(profile.words.contains("cross country") && profile.words.contains("trumpet") && profile.words.contains("gunner"))
        let kept = EmailCalendar.relevant(items, to: profile)
        let titles = kept.map(\.title)
        #expect(kept.count == 16)
        #expect(titles.contains("Cross country regional championship"))
        #expect(titles.contains("Trumpet and brass sectional"))
        #expect(titles.contains("Winter band concert"))
        #expect(titles.contains("Lacrosse interest meeting for spring"))
        #expect(titles.contains("8th grade field trip to the Battleship North Carolina"))
        #expect(titles.contains("No school"))
        #expect(!titles.contains(where: { $0.contains("6th grade") || $0.contains("orchestra") || $0.contains("Chess") || $0.contains("Drama") || $0.contains("Swim") }))
    }

    @Test func withoutAProfileOnlySchoolWideDays() throws {
        let items = EmailCalendar.items(in: try Self.newsletter(), received: Self.received, calendar: Self.cal)
        let kept = EmailCalendar.relevant(items, to: EmailCalendar.Profile(""))
        #expect(kept.count == 7)
        #expect(kept.allSatisfy { $0.section == "ALL GRADES" })
    }

    @Test func weekdayOnlyLinesAreNotDates() {
        let text = "Weekly runs\nTuesday 6 PM track, Thursday 6 AM river loop, Saturday 7 AM long run."
        #expect(EmailCalendar.items(in: text, received: Self.received, calendar: Self.cal).isEmpty)
    }

    @Test func wrappedPDFLinesJoinTheLineAbove() {
        let text = "BAND\n• Thu Dec 10: Winter band concert, 6:30 PM in the gym. Band students arrive\nat 5:45 PM in concert black."
        let items = EmailCalendar.items(in: text, received: Self.received, calendar: Self.cal)
        #expect(items.count == 1)
        #expect(items[0].line.hasSuffix("concert black."))
    }

    @Test func titlesDropTheDate() {
        #expect(EmailCalendar.title(of: "Sat Nov 7: Cross country regional championship, 8:30 AM start") == "Cross country regional championship")
        #expect(EmailCalendar.title(of: "Nov 25 to 27: No school, Thanksgiving break.") == "No school")
        #expect(EmailCalendar.title(of: "Picture retake day is Wednesday, November 4. Forms were sent home.") == "Picture retake day is Wednesday")
    }

    @Test func numericAndLongDates() {
        #expect(EmailCalendar.firstDay(in: "Forms due 11/13", received: Self.received, calendar: Self.cal) == Self.day(11, 13))
        #expect(EmailCalendar.firstDay(in: "Outbound: Friday, December 18, 2026", received: Self.received, calendar: Self.cal) == Self.day(12, 18))
        #expect(EmailCalendar.firstDay(in: "Opens Jan 5", received: Self.received, calendar: Self.cal) == Self.cal.date(from: DateComponents(year: 2027, month: 1, day: 5)))
        #expect(EmailCalendar.firstDay(in: "See https://x.com/a/1/2/b", received: Self.received, calendar: Self.cal) == nil)
    }
}

struct EmailNoticeTests {
    @Test func signInCodesAreNotPosts() {
        #expect(EmailRules.isAccountNotice(subject: "Your verification code", text: "Your verification code is 482913."))
        #expect(EmailRules.isAccountNotice(subject: "New sign-in to your account", text: ""))
        #expect(!EmailRules.isAccountNotice(subject: "Your trip: Charlotte to Denver", text: "Confirmation code: KQ7M2P"))
    }

    @Test func subjectsLoseTheirClutter() {
        #expect(EmailRules.cleanSubject("[Shoebox test 8] Fwd: Fwd: Re: Dock repair quote") == "Dock repair quote")
        #expect(EmailRules.cleanSubject("RE: fw: Lunch") == "Lunch")
        #expect(EmailRules.cleanSubject("Q4 Planning Notes") == "Q4 Planning Notes")
    }

    @Test func inventedDetailsAreCaught() {
        let src = "Ask Mom if she wants the garden kneeler pad for Christmas. She mentioned hers is worn out."
        #expect(EmailRules.invents("Ask Mom about the kneeler pad for Christmas today at home.", source: src))
        #expect(!EmailRules.invents("Ask Mom if she wants the garden kneeler pad for Christmas.", source: src))
        let receipt = "Total $48.64. Return policy: 90 days with receipt."
        #expect(!EmailRules.invents("Total $48.64. Keep the receipt for 90-day returns.", source: receipt))
        #expect(EmailRules.invents("Total $49.64.", source: receipt))
    }
}
