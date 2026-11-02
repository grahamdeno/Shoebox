import Foundation
import Testing
@testable import ShoeboxCore

/// C-2: a forwarded message's header lines carry the forwarder's day and people, never an event.
struct ForwardHeaderTests {
    @Test func headerLinesAreRecognised() {
        let headers = [
            "From: Rita Cole <rita@example.com>", "Sent: Monday, November 9, 2026 9:15 AM", "Date: Mon, 9 Nov 2026", "Subject: Dock repair",
            "To: Sam", "Cc: Dan <dan@example.com>", "Bcc: x@example.com", "Reply-To: rita@example.com", "Importance: High",
            "---------- Forwarded message ---------",
            "Envoy\u{00E9} : lundi 9 novembre 2026", "Objet : Devis", "\u{00C0} : Sam", "De : Rita",
            "Enviado el: lunes, 9 de noviembre", "Asunto: Presupuesto", "Para: Sam",
            "Gesendet: Montag, 9. November 2026", "Betreff: Angebot", "Von: Rita",
            "  sent:  Monday", "CC: a@b.com",
        ]
        for h in headers { #expect(EmailRules.isForwardHeader(h), "\(h)") }
    }

    @Test func ordinaryLinesAreNotHeaders() {
        let lines = [
            "Sent from my iPhone", "Please send: the form by Friday", "Total: $4,150", "To the parents: the concert is Thursday.",
            "Date night is Friday", "Tickets are free.", "From the principal's desk", "Reply to this email if you can come",
            "Subjects covered: maths and science", "Cc the office on your answer",
        ]
        for l in lines { #expect(!EmailRules.isForwardHeader(l), "\(l)") }
    }

    @Test func anOutlookSentLineDoesNotMakeAnEvent() {
        let forwarded = """
        From: Rita Cole
        Sent: Monday, November 9, 2026 9:15 AM
        To: Sam
        Cc: Dan
        Subject: Dock repair quote

        The total is $4,150.
        """
        let cal = EmailRulesTests.cal, received = EmailRulesTests.received   // Wed Nov 4 2026
        let kept = forwarded.components(separatedBy: "\n").filter { !EmailRules.isForwardHeader($0) }.joined(separator: "\n")
        #expect(EmailRules.days(in: kept, received: received, calendar: cal).isEmpty)
        #expect(!EmailRules.days(in: forwarded, received: received, calendar: cal).isEmpty, "the header alone would have made a false event")
    }

    @Test func dayBeforeMonthInAnEmail() {
        let cal = EmailRulesTests.cal, received = EmailRulesTests.received
        let days = EmailRules.days(in: "Class photos on 12 November, forms back by the 5th of Nov.", received: received, calendar: cal)
        #expect(days.contains(EmailCalendarTests.day(11, 12)))
        #expect(days.contains(EmailCalendarTests.day(11, 5)))
    }
}
