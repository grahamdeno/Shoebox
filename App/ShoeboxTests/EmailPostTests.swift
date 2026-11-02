import XCTest
@testable import Shoebox

final class EmailPostTests: XCTestCase {
    func testPlainKeepsAShortGistNotTheEmail() {
        let lines = ["Hi Graham,", "Your son's band concert is Thursday, Nov 13 at 7 pm in the school gym.",
                     "Please have him there by 6:30 in black pants and a white shirt.",
                     "Tickets are free. Families may bring a canned food item for the drive."]
            + (1...40).map { "More news item \($0) that goes on and on about things nobody needs to read today." }
            + ["Unsubscribe | Privacy Policy", "All rights reserved."]
        let w = EmailPost.plain(subject: "Winter Band Concert", lines: lines)
        XCTAssertEqual(w.title, "Winter Band Concert")
        XCTAssertLessThanOrEqual(w.text.count, 330)
        XCTAssertTrue(w.text.contains("Nov 13 at 7 pm"))
        XCTAssertFalse(w.text.contains("More news item 10"))
        XCTAssertFalse(w.text.lowercased().contains("unsubscribe"))
    }

    func testPlainWithoutSubjectUsesFirstLine() {
        let w = EmailPost.plain(subject: "", lines: ["Dentist reminder for Heidi", "Tuesday at 3:15 pm."])
        XCTAssertEqual(w.title, "Dentist reminder for Heidi")
        XCTAssertTrue(w.text.contains("3:15"))
    }

    func testPlainReadsQuotedRepliesAndCleansTheSubject() {
        let lines = ["> On Sun, Oct 25, Rita Cole wrote:", "> > Hi Dan, can you send over the quote for the dock?",
                     "> Replace 2 pilings: $2,800", "> Total: $4,150", "Thoughts? Need to decide by the 15th.", "Sent from my iPhone"]
        let w = EmailPost.plain(subject: "[List] Fwd: Fwd: Re: Dock repair quote", lines: lines)
        XCTAssertEqual(w.title, "Dock repair quote")
        XCTAssertTrue(w.text.contains("$4,150"))
        XCTAssertFalse(w.text.contains(">"))
        XCTAssertFalse(w.text.contains("wrote:"))
        XCTAssertFalse(w.text.contains("iPhone"))
    }
}
