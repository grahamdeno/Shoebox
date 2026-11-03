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

/// The same post from email made twice is kept once; next week's newsletter with the same title is not a repeat.
@MainActor
final class InboxRepeatTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_793_000_000)

    private func post(_ title: String, _ body: String, at: Date) -> Save {
        let s = Save(title: title, body: body, kind: .email, createdAt: at)
        s.emailReceivedAt = at
        return s
    }

    func testTheSameNoticeTwiceIsARepeat() {
        let kept = [post("Picture retake day", "Thursday, Nov 6\nPicture retake day is Thursday in the gym.", at: day)]
        XCTAssertTrue(Inbox.isRepeat(title: "Picture retake day", text: "Thursday, Nov 6\nPicture retake day is Thursday in the gym.",
                                     received: day.addingTimeInterval(3_600), in: kept))
        XCTAssertTrue(Inbox.isRepeat(title: "picture retake day", text: "Thursday, Nov 6\nPicture retake day is Thursday in the gym.",
                                     received: day, in: kept), "case does not matter")
    }

    func testSameTitleNewWordsIsNotARepeat() {
        let kept = [post("26-27 Duck Weekly Newsletter", "Band concert Thursday.", at: day)]
        XCTAssertFalse(Inbox.isRepeat(title: "26-27 Duck Weekly Newsletter", text: "Book fair all week.",
                                      received: day.addingTimeInterval(7 * 86_400), in: kept))
    }

    func testLongAgoOrDeletedIsNotARepeat() {
        let old = post("Picture retake day", "Same words.", at: day)
        XCTAssertFalse(Inbox.isRepeat(title: "Picture retake day", text: "Same words.", received: day.addingTimeInterval(15 * 86_400), in: [old]))
        let gone = post("Picture retake day", "Same words.", at: day)
        gone.deletedAt = day
        XCTAssertFalse(Inbox.isRepeat(title: "Picture retake day", text: "Same words.", received: day, in: [gone]))
    }

    func testOnlyEmailPostsCount() {
        let note = Save(title: "Picture retake day", body: "Same words.", kind: .note, createdAt: day)
        XCTAssertFalse(Inbox.isRepeat(title: "Picture retake day", text: "Same words.", received: day, in: [note]))
    }
}
