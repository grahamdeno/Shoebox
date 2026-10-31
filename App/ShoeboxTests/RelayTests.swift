import XCTest
@testable import Shoebox

/// The relay answers only requests that carry Shoebox's Origin header.
final class RelayTests: XCTestCase {
    func testPreviewRequestCarriesTheOriginHeader() {
        let req = Relay.request("preview", query: [.init(name: "url", value: "https://example.com/a?b=1")])
        XCTAssertEqual(req.value(forHTTPHeaderField: "Origin"), "https://inmyshoebox.com")
        XCTAssertEqual(req.httpMethod, "GET")
        XCTAssertEqual(req.url?.host(), "shoebox-api.tangomike.app")
        XCTAssertEqual(req.url?.path(), "/preview")
        XCTAssertTrue(req.url?.query?.contains("url=") ?? false)
    }

    func testInboxRequestCarriesTheKeyAndOrigin() {
        let body = Data("{}".utf8)
        let req = Relay.request("inbox", method: "POST", body: body, key: "abc")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Origin"), "https://inmyshoebox.com")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-inbox-key"), "abc")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(req.httpBody, body)
    }

    func testStoreOpensWithCloudKitOff() throws {
        // Store.make passes cloudKitDatabase: .none. With the iCloud entitlement present, a store
        // left on automatic would try to sync, so opening cleanly here is the check.
        XCTAssertNoThrow(try Store.make(inMemory: true))
    }
}
