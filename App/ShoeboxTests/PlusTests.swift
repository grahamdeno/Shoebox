import XCTest
@testable import Shoebox

/// SPEC 9: Plus is offered a week after the first run, never in it. Review and TestFlight builds (the App Store
/// sandbox) offer it at once, so a reviewer can reach it.
@MainActor
final class PlusTests: XCTestCase {
    private let now = Date()

    func testNotInTheFirstWeekOnTheStore() {
        XCTAssertFalse(Plus.isOffered(now: now, firstOpened: now, hasAddress: false, sandbox: false))
        XCTAssertFalse(Plus.isOffered(now: now, firstOpened: now.addingTimeInterval(-Plus.offerAfter + 60), hasAddress: false, sandbox: false))
        XCTAssertFalse(Plus.isOffered(now: now, firstOpened: nil, hasAddress: false, sandbox: false))
    }

    func testAfterAWeekOnTheStore() {
        XCTAssertTrue(Plus.isOffered(now: now, firstOpened: now.addingTimeInterval(-Plus.offerAfter), hasAddress: false, sandbox: false))
    }

    func testAtOnceInReviewAndTestFlight() {
        XCTAssertTrue(Plus.isOffered(now: now, firstOpened: now, hasAddress: false, sandbox: true))
        XCTAssertTrue(Plus.isOffered(now: now, firstOpened: nil, hasAddress: false, sandbox: true))
    }

    func testAlwaysWithAnAddress() {
        XCTAssertTrue(Plus.isOffered(now: now, firstOpened: now, hasAddress: true, sandbox: false))
    }

    /// TestFlight and App Review send the install's proof as `beta`; a real purchase goes as `purchase` (decided November 5).
    func testAccessGoesInItsOwnField() {
        XCTAssertEqual(Plus.Access.purchase("p").field.key, "purchase")
        XCTAssertEqual(Plus.Access.beta("b").field.key, "beta")
        XCTAssertEqual(Plus.Access.beta("b").field.value, "b")
    }

    /// A tester code goes in its own field (decided November 6).
    func testCodeGoesInItsOwnField() {
        XCTAssertEqual(Plus.Access.code("plum-otter-4821").field.key, "code")
        XCTAssertEqual(Plus.Access.code("plum-otter-4821").field.value, "plum-otter-4821")
    }
}
