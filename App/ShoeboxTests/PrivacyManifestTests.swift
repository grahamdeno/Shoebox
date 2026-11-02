import XCTest

/// P-2 and P-3: the privacy manifests say what Shoebox does. This reads the files from the source tree.
final class PrivacyManifestTests: XCTestCase {
    private func manifest(_ path: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appending(path: path))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    func testTheAppManifestMatchesWhatIsCollected() throws {
        let m = try manifest("App/Shoebox/PrivacyInfo.xcprivacy")
        XCTAssertEqual(m["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((m["NSPrivacyTrackingDomains"] as? [Any])?.count, 0)
        let collected = try XCTUnwrap(m["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        XCTAssertEqual(Set(collected.compactMap { $0["NSPrivacyCollectedDataType"] as? String }), [
            "NSPrivacyCollectedDataTypeEmailAddress", "NSPrivacyCollectedDataTypeName",
            "NSPrivacyCollectedDataTypeEmailsOrTextMessages", "NSPrivacyCollectedDataTypeOtherUserContent",
        ])
        for item in collected {
            XCTAssertEqual(item["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
            XCTAssertEqual(item["NSPrivacyCollectedDataTypePurposes"] as? [String], ["NSPrivacyCollectedDataTypePurposeAppFunctionality"])
        }
        XCTAssertFalse(String(describing: m).contains("Analytics"), "the app sends no analytics")
    }

    func testBothTargetsDeclareUserDefaults() throws {
        for path in ["App/Shoebox/PrivacyInfo.xcprivacy", "Share/PrivacyInfo.xcprivacy"] {
            let m = try manifest(path)
            let apis = try XCTUnwrap(m["NSPrivacyAccessedAPITypes"] as? [[String: Any]], path)
            let defaults = try XCTUnwrap(apis.first { $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults" }, path)
            XCTAssertEqual(Set(try XCTUnwrap(defaults["NSPrivacyAccessedAPITypeReasons"] as? [String])), ["CA92.1", "1C8F.1"], path)
        }
    }

    func testTheShareExtensionCollectsNothingItself() throws {
        let m = try manifest("Share/PrivacyInfo.xcprivacy")
        XCTAssertEqual((m["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0)
        XCTAssertEqual(m["NSPrivacyTracking"] as? Bool, false)
    }
}
