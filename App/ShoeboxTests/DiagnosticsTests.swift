import XCTest
@testable import Shoebox

/// Q-2: crash and hang reports are kept on the phone, the newest 20.
final class DiagnosticsTests: XCTestCase {
    func testOnlyTheNewestAreKept() {
        let names = (1...25).map { String(format: "20261102-%06d-diagnostics-abc123.json", $0) } + ["notes.txt"]
        let drop = Diagnostics.oldest(in: names.shuffled())
        XCTAssertEqual(drop.count, 5)
        XCTAssertEqual(drop, (1...5).map { String(format: "20261102-%06d-diagnostics-abc123.json", $0) })
        XCTAssertEqual(Diagnostics.oldest(in: Array(names.prefix(20))), [])
    }

    func testNamesSortByDate() {
        let a = Diagnostics.name(kind: "metrics", now: Date(timeIntervalSince1970: 1_793_595_660))
        let b = Diagnostics.name(kind: "metrics", now: Date(timeIntervalSince1970: 1_793_682_060))
        XCTAssertLessThan(a, b)
        XCTAssertTrue(a.hasPrefix("20261102-"))
        XCTAssertTrue(a.hasSuffix(".json"))
    }
}
