import CryptoKit
import XCTest
@testable import Shoebox

/// R-13: the phone opens what the relay seals. The relay's tests write relay/app/test/vectors/sealed-v1.json and this
/// opens that same file with CryptoKit. A missing file skips (it is committed once the relay's packages are installed).
@MainActor
final class SealedMailTests: XCTestCase {
    private func vectors(_ name: String) throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../relay/app/test/vectors/\(name)").standardized
        guard let data = try? Data(contentsOf: url) else { throw XCTSkip("\(name) is not committed yet") }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testOpensWhatTheRelaySealed() throws {
        let v = try vectors("sealed-v1.json")
        let secret = try XCTUnwrap(Data(base64Encoded: v["recipientSecret"] as! String))
        let key = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: secret)
        let opened = try XCTUnwrap(SealedMail.openBase64(enc: v["enc"] as? String, ct: v["ct"] as? String, aad: v["aad"] as! String, with: key))
        XCTAssertEqual(String(decoding: opened, as: UTF8.self), v["plaintext"] as? String)
        XCTAssertEqual(v["info"] as? String, String(decoding: SealedMail.info, as: UTF8.self))
    }

    func testAWrongAadDoesNotOpenTheRelaysRecord() throws {
        let v = try vectors("sealed-v1.json")
        let key = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: XCTUnwrap(Data(base64Encoded: v["recipientSecret"] as! String)))
        XCTAssertNil(SealedMail.openBase64(enc: v["enc"] as? String, ct: v["ct"] as? String, aad: (v["aad"] as! String) + "x", with: key))
    }

    func testRoundTripAndWrongAad() throws {
        let key = Curve25519.KeyAgreement.PrivateKey()
        let sealed = try SealedMail.seal(Data("hello".utf8), aad: "box:id", to: key.publicKey)
        XCTAssertEqual(try SealedMail.open(enc: sealed.enc, ct: sealed.ct, aad: "box:id", with: key), Data("hello".utf8))
        XCTAssertThrowsError(try SealedMail.open(enc: sealed.enc, ct: sealed.ct, aad: "box:other", with: key))
        XCTAssertThrowsError(try SealedMail.open(enc: sealed.enc, ct: sealed.ct, aad: "box:id", with: Curve25519.KeyAgreement.PrivateKey()))
    }

    func testRFC9180AppendixA1() throws {
        let v = try vectors("rfc9180-a1.json")
        func hex(_ s: String) -> Data { Data(stride(from: 0, to: s.count, by: 2).map { i in
            let a = s.index(s.startIndex, offsetBy: i); return UInt8(s[a..<s.index(a, offsetBy: 2)], radix: 16)! }) }
        let suite = HPKE.Ciphersuite(kem: .Curve25519_HKDF_SHA256, kdf: .HKDF_SHA256, aead: .AES_GCM_128)
        let first = (v["encryptions"] as! [[String: Any]])[0]
        let key = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: hex(v["skRm"] as! String))
        var r = try HPKE.Recipient(privateKey: key, ciphersuite: suite, info: hex(v["info"] as! String), encapsulatedKey: hex(v["enc"] as! String))
        let pt = try r.open(hex(first["ct"] as! String), authenticating: hex(first["aad"] as! String))
        XCTAssertEqual(pt, hex(first["pt"] as! String))
    }

    // MARK: Inbox.opened

    private func sealedMail(id: String, box: String, to key: Curve25519.KeyAgreement.PublicKey, subject: String) throws -> Inbox.Mail {
        let body = try JSONSerialization.data(withJSONObject: ["from": "a@b.com", "subject": subject, "text": "hi"])
        let s = try SealedMail.seal(body, aad: "\(box):\(id)", to: key)
        return Inbox.Mail(id: id, v: 1, enc: s.enc.base64EncodedString(), ct: s.ct.base64EncodedString(), at: 1)
    }

    func testOpenedReadsASealedMailAndAPlainOne() throws {
        let key = Curve25519.KeyAgreement.PrivateKey()
        let sealed = try sealedMail(id: "m1", box: "b", to: key.publicKey, subject: "Concert")
        XCTAssertEqual(Inbox.opened(sealed, box: "b", key: key)?.subject, "Concert")
        let plain = Inbox.Mail(id: "m2", subject: "Old", text: "x")
        XCTAssertEqual(Inbox.opened(plain, box: "b", key: key)?.subject, "Old")
    }

    func testOpenedRefusesAnotherKeyAnotherBoxAndAnUnknownVersion() throws {
        let key = Curve25519.KeyAgreement.PrivateKey()
        let sealed = try sealedMail(id: "m1", box: "b", to: key.publicKey, subject: "Concert")
        XCTAssertNil(Inbox.opened(sealed, box: "b", key: Curve25519.KeyAgreement.PrivateKey()))
        XCTAssertNil(Inbox.opened(sealed, box: "other", key: key))
        var future = sealed
        future.v = 2
        XCTAssertNil(Inbox.opened(future, box: "b", key: key))
    }

    // Fix 3: mail this phone can't open stays on the relay for 2 days.

    func testUnopenedMailStaysTwoDays() {
        let now = Date()
        let ms = { (ago: TimeInterval) in (now.timeIntervalSince1970 - ago) * 1000 }
        XCTAssertFalse(Inbox.mayDropUnopened(at: ms(60), now: now))
        XCTAssertFalse(Inbox.mayDropUnopened(at: ms(Inbox.keepUnopened - 60), now: now))
        XCTAssertTrue(Inbox.mayDropUnopened(at: ms(Inbox.keepUnopened), now: now))
        XCTAssertFalse(Inbox.mayDropUnopened(at: nil, now: now), "without a time, the relay's 7 days decide")
    }

    func testAMailWithoutAKeyIsNotOpenedButAPlainOneIs() throws {
        let key = Curve25519.KeyAgreement.PrivateKey()
        let sealed = try sealedMail(id: "m1", box: "b", to: key.publicKey, subject: "Concert")
        XCTAssertNil(Inbox.opened(sealed, box: "b", key: nil))
        XCTAssertEqual(Inbox.opened(Inbox.Mail(id: "m2", subject: "Old"), box: "b", key: nil)?.subject, "Old")
    }

    func testUnopenedMailIsCountedForAWeek() {
        let d = AppGroup.defaults
        let (n, at) = (d.integer(forKey: "unopenedMail"), d.object(forKey: "unopenedMailAt"))
        defer { d.set(n, forKey: "unopenedMail"); d.set(at, forKey: "unopenedMailAt") }
        Prefs.unopenedMail = 0
        Prefs.unopenedMailAt = nil
        XCTAssertNil(Inbox.unopenedLine())
        let now = Date()
        Inbox.noteUnopened(1, now: now)
        XCTAssertEqual(Inbox.unopenedLine(now: now), "1 email couldn't be opened on this phone.")
        Inbox.noteUnopened(2, now: now)
        XCTAssertEqual(Inbox.unopenedLine(now: now), "3 emails couldn't be opened on this phone.")
        XCTAssertNil(Inbox.unopenedLine(now: now.addingTimeInterval(8 * 86_400)))
    }
}
