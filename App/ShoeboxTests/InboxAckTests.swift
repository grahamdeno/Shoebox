import XCTest
@testable import Shoebox

/// D-2: mail is acknowledged (and so deleted from the relay) only after the posts made from it are saved.
@MainActor
final class InboxAckTests: XCTestCase {
    private struct Boom: Error {}

    func testAcknowledgesAfterTheSave() async {
        var order: [String] = []
        let ok = await Inbox.commit(done: ["a", "b"], save: { order.append("save") },
                                    acknowledge: { ids in order.append("ack:" + ids.joined(separator: ",")) })
        XCTAssertTrue(ok)
        XCTAssertEqual(order, ["save", "ack:a,b"])
    }

    func testAFailedSaveAcknowledgesNothing() async {
        var acked = false
        let ok = await Inbox.commit(done: ["a"], save: { throw Boom() }, acknowledge: { _ in acked = true })
        XCTAssertFalse(ok)
        XCTAssertFalse(acked, "the mail must stay on the relay so the next collection can try again")
    }

    func testNothingHandledMeansNothingToAcknowledge() async {
        var acked = false
        let ok = await Inbox.commit(done: [], save: {}, acknowledge: { _ in acked = true })
        XCTAssertTrue(ok)
        XCTAssertFalse(acked)
    }
}
