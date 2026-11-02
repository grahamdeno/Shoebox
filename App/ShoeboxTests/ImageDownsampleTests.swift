import ImageIO
import UIKit
import XCTest
@testable import Shoebox

/// D-3: big photos are shrunk while they are read, never decoded whole.
final class ImageDownsampleTests: XCTestCase {
    private func jpeg(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor(hex: 0x56395F).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor(hex: 0xFFBD76).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        }
        return image.jpegData(compressionQuality: 0.9)!
    }

    private func size(of data: Data) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let s = ImageDownsample.pixelSize(of: source) else { return nil }
        return (s.width, s.height)
    }

    func testAFileIsShrunkToTheLongestSide() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "big-\(UUID().uuidString).jpg")
        try jpeg(width: 4000, height: 3000).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let out = try XCTUnwrap(ImageDownsample.jpeg(fromFile: url, maxPixel: 2400))
        let s = try XCTUnwrap(size(of: out))
        XCTAssertEqual(s.0, 2400)
        XCTAssertEqual(s.1, 1800)
        XCTAssertLessThan(out.count, 4_000_000)
    }

    func testAPictureSmallerThanTheLimitIsNotEnlarged() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "small-\(UUID().uuidString).jpg")
        try jpeg(width: 800, height: 600).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let s = try XCTUnwrap(size(of: try XCTUnwrap(ImageDownsample.jpeg(fromFile: url, maxPixel: 2400))))
        XCTAssertEqual(s.0, 800)
    }

    func testNotAPictureGivesNothing() {
        XCTAssertNil(ImageDownsample.jpeg(from: Data("not a picture".utf8), maxWidth: 1200))
        XCTAssertNil(ImageDownsample.jpeg(fromFile: URL(fileURLWithPath: "/nonexistent/photo.jpg")))
    }

    func testTheWidthRuleIsKeptWhateverWayThePictureIsTurned() {
        XCTAssertEqual(ImageDownsample.longestSide(width: 4000, height: 3000, maxWidth: 1200), 1200)
        // A portrait 3000 x 4000 picture is sized by its width: 1600 wide, about 2133 tall.
        XCTAssertEqual(ImageDownsample.longestSide(width: 3000, height: 4000, maxWidth: 1600), 2133)
        XCTAssertEqual(ImageDownsample.longestSide(width: 500, height: 400, maxWidth: 1200), 500)
    }

    func testThumbnailKeepsTheOldRules() throws {
        let landscape = try XCTUnwrap(Relay.thumbnail(jpeg(width: 4000, height: 3000), maxWidth: 1200))
        let l = try XCTUnwrap(size(of: landscape))
        XCTAssertEqual(l.0, 1200)
        XCTAssertEqual(l.1, 900)
        let portrait = try XCTUnwrap(Relay.thumbnail(jpeg(width: 3000, height: 4000), maxWidth: 1600))
        let p = try XCTUnwrap(size(of: portrait))
        XCTAssertEqual(p.0, 1600, accuracy: 1)
        XCTAssertEqual(p.1, 2133, accuracy: 1)
        // Icons and logos are refused.
        XCTAssertNil(Relay.thumbnail(jpeg(width: 100, height: 100)))
        XCTAssertNil(Relay.thumbnail(jpeg(width: 1000, height: 100)))
    }
}
