import Foundation
import Testing
@testable import ShoeboxCore

/// C-14: Canada, the UK, Australia and New Zealand write "10/11" as 10 November and use "Year 4", not "4th grade".
struct DayFirstTests {
    static var cal: Calendar { EmailCalendarTests.cal }
    static var received: Date { EmailCalendarTests.received }   // Mon Nov 2 2026
    static func day(_ m: Int, _ d: Int) -> Date { EmailCalendarTests.day(m, d) }

    @Test func theRegionDecidesWhichOrder() {
        for id in ["en_GB", "en_CA", "fr_CA", "en_AU", "en_NZ"] { #expect(EmailCalendar.dayFirst(for: Locale(identifier: id)), "\(id)") }
        for id in ["en_US", "es_MX", "es_US"] { #expect(!EmailCalendar.dayFirst(for: Locale(identifier: id)), "\(id)") }
    }

    @Test func aNumericDateFollowsTheRegion() {
        let line = "Tue 10/11: Options evening, 6:00 PM"
        #expect(EmailCalendar.firstDay(in: line, received: Self.received, calendar: Self.cal, dayFirst: true) == Self.day(11, 10))
        #expect(EmailCalendar.firstDay(in: line, received: Self.received, calendar: Self.cal, dayFirst: false) == Self.day(10, 11))
    }

    @Test func aNumberOverTwelveIsTheDayWhateverTheRegion() {
        for dayFirst in [true, false] {
            #expect(EmailCalendar.firstDay(in: "Carols 25/12", received: Self.received, calendar: Self.cal, dayFirst: dayFirst) == Self.day(12, 25))
            #expect(EmailCalendar.firstDay(in: "Carols 12/25", received: Self.received, calendar: Self.cal, dayFirst: dayFirst) == Self.day(12, 25))
        }
        #expect(EmailCalendar.monthAndDay(31, 31, dayFirst: true) == nil)
        #expect(EmailCalendar.monthAndDay(0, 5, dayFirst: false) == nil)
    }

    @Test func aDayWrittenBeforeTheMonth() {
        let c = Self.cal, r = Self.received
        #expect(EmailCalendar.firstDay(in: "Mon 2 Nov: Picture retake day", received: r, calendar: c) == Self.day(11, 2))
        #expect(EmailCalendar.firstDay(in: "Class photos on 12 November", received: r, calendar: c) == Self.day(11, 12))
        #expect(EmailCalendar.firstDay(in: "Forms back by the 5th of Nov", received: r, calendar: c) == Self.day(11, 5))
        #expect(EmailCalendar.firstDay(in: "Sports day 14th November 2026", received: r, calendar: c) == Self.day(11, 14))
        #expect(EmailCalendar.firstDay(in: "INSET days 25-27 Nov", received: r, calendar: c) == Self.day(11, 25))
        #expect(EmailCalendar.firstDay(in: "Closed 25 to 27 Nov", received: r, calendar: c) == Self.day(11, 25))
        // Month first still reads as before.
        #expect(EmailCalendar.firstDay(in: "Sat Nov 7: Cross country", received: r, calendar: c) == Self.day(11, 7))
    }

    @Test func aLowercaseMayIsTheVerb() {
        #expect(EmailCalendar.firstDay(in: "Up to 10 may attend the trip", received: Self.received, calendar: Self.cal) == nil)
        let may = EmailCalendar.firstDay(in: "Sports day 10 May", received: Self.received, calendar: Self.cal)
        #expect(may == EmailCalendarTests.cal.date(from: DateComponents(year: 2027, month: 5, day: 10)))
    }

    @Test func marathonIsNotMarch() {
        #expect(EmailCalendar.firstDay(in: "Bring 10 marathon runners", received: Self.received, calendar: Self.cal) == nil)
    }

    static let ukNewsletter = """
    ALL YEARS
    - Mon 2 Nov: Picture retake day, forms in the front office.
    - Fri 6 Nov: Spirit Day, wear school colours.
    - Wed 11 Nov: Remembrance assembly, 9:00 AM in the hall.
    - 25-27 Nov: INSET days.
    YEAR 4
    - Thu 5 Nov: Class assembly, 2:00 PM.
    YEAR 9
    - Tue 10 Nov: Options evening, 6:00 PM.
    """

    @Test func aUKNewsletterBecomesOnePostPerDate() {
        let items = EmailCalendar.items(in: Self.ukNewsletter, received: Self.received, calendar: Self.cal, dayFirst: true)
        #expect(items.count == 6)
        #expect(items.first?.day == Self.day(11, 2))
        #expect(items.first?.section == "ALL YEARS")
        #expect(EmailCalendar.details(of: items[0], received: Self.received, calendar: Self.cal) == "Monday, Nov 2 \u{00B7} Forms in the front office.")
        #expect(EmailCalendar.details(of: items[3], received: Self.received, calendar: Self.cal) == "Wednesday, Nov 25 to Friday, Nov 27.")
        #expect(items[3].title == "INSET days")
    }

    @Test func yearLevelsPickTheRightPosts() {
        let items = EmailCalendar.items(in: Self.ukNewsletter, received: Self.received, calendar: Self.cal, dayFirst: true)
        let kept = EmailCalendar.relevant(items, to: EmailCalendar.Profile("Sam, Year 4: football, band")).map(\.title)
        #expect(kept.contains("Class assembly"))
        #expect(kept.contains("Picture retake day"))
        #expect(!kept.contains("Options evening"))
        #expect(kept.count == 5)
    }

    @Test func yearLevelsInAProfile() {
        let p = EmailCalendar.Profile("Sam, Year 4: football, band")
        #expect(p.grades == [4])
        #expect(p.words.contains("sam") && p.words.contains("football") && p.words.contains("band"))
        #expect(!p.words.contains(where: { $0.contains("year") }))
        #expect(EmailCalendar.Profile("Mia Yr 11, Year 13 prom").grades == [11, 13])
        #expect(EmailCalendar.Profile("Sam, 4th grade: soccer, band").grades == [4])
    }

    @Test func yearThatIsNotASchoolYear() {
        #expect(EmailCalendar.grades(in: "we do this year 5 times") == [])
        #expect(EmailCalendar.grades(in: "yearbook orders close friday") == [])
        #expect(EmailCalendar.grades(in: "year 2026 review") == [])
        #expect(EmailCalendar.grades(in: "year 7 camp") == [7])
        #expect(EmailCalendar.grades(in: "year 14") == [])
    }
}
