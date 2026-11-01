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
}
