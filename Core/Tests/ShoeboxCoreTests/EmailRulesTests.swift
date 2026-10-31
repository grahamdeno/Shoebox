import Foundation
import Testing
@testable import ShoeboxCore

struct EmailRulesTests {
    static var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }
    static let received = Date(timeIntervalSince1970: 1_793_818_800)   // Wed Nov 4 2026

    @Test func uspsIsPromotional() {
        #expect(EmailRules.kind(from: "USPSInformeddelivery@email.informeddelivery.usps.com", fromName: "USPS Informed Delivery",
                                subject: "Your Daily Digest", text: "", hasOwnNote: false) == .promotional)
    }

    @Test func storeBlastIsPromotional() {
        let t = "Big savings! 40% off everything. Shop now. Use promo code FALL. Unsubscribe"
        #expect(EmailRules.kind(from: "hello@store.com", fromName: "Store", subject: "Sale", text: t, hasOwnNote: false) == .promotional)
    }

    @Test func yourNoteKeepsIt() {
        #expect(EmailRules.kind(from: "USPSInformeddelivery@usps.com", fromName: "", subject: "", text: "", hasOwnNote: true) == .other)
    }

    @Test func schoolMailIsNotPromotional() {
        let t = "Report cards go home Thursday. No school Nov 3. PTSA meeting Nov 4."
        #expect(EmailRules.kind(from: "principal@district.example.org", fromName: "Lincoln Middle", subject: "Weekly updates", text: t, hasOwnNote: false) == .other)
    }

    @Test func stripsAdsAndFooter() {
        let t = "Picture day is Nov 19.\nSponsored by Joe's Pizza\nGet 20% off with code SCHOOL\nBring a coat.\nUnsubscribe here\nPrivacy policy"
        #expect(EmailRules.stripAds(t) == "Picture day is Nov 19.\nBring a coat.")
    }

    @Test func promotionPostIsCaught() {
        #expect(EmailRules.looksLikePromotion("Save 20% off spirit wear, shop now"))
        #expect(!EmailRules.looksLikePromotion("No school Monday for the teacher workday"))
    }

    @Test func quoteMustBeInTheEmail() {
        let email = "Report Cards go home on Thursday, the 29th of October. Halloween Dance is 4:00-6:00 in the gym."
        #expect(EmailRules.quoteFound("Report cards go home on Thursday", in: email))
        #expect(!EmailRules.quoteFound("Book fair runs all week in the library", in: email))
    }

    @Test func daysNamedInTheEmail() {
        let days = EmailRules.days(in: "No school Nov 11. Club Day on Friday. Turkey Trot November 24th.", received: Self.received, calendar: Self.cal)
        func d(_ m: Int, _ day: Int) -> Date { Self.cal.startOfDay(for: Self.cal.date(from: DateComponents(year: 2026, month: m, day: day))!) }
        #expect(days.contains(d(11, 11)))
        #expect(days.contains(d(11, 6)))     // Friday after it arrived
        #expect(days.contains(d(11, 24)))
        #expect(!days.contains(d(12, 25)))
    }

    @Test func htmlBecomesText() {
        let html = "<html><head><title>x</title></head><body><script>var a=1</script><h1>Week Ahead</h1><ul><li>Mon: No school</li><li>Thu: Report cards</li></ul><p>Tickets &amp; info</p></body></html>"
        let t = EmailRules.text(fromHTML: html)
        #expect(t.contains("Week Ahead"))
        #expect(t.contains("- Mon: No school"))
        #expect(t.contains("Tickets & info"))
        #expect(!t.contains("var a"))
    }
}
