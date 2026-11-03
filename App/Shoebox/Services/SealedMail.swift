import CryptoKit
import Foundation

/// Opening mail the relay sealed to this phone (docs/design/identity-and-sealed-mail.md, R-13).
///
/// HPKE, RFC 9180, base mode: DHKEM(X25519, HKDF-SHA256), HKDF-SHA256, AES-256-GCM. CryptoKit has it built in; nothing
/// is hand-rolled. The relay seals with `@hpke/core`. The two agree byte for byte: the relay's tests write
/// relay/app/test/vectors/sealed-v1.json and SealedMailTests opens that same file.
///
///   info = "shoebox-mail-v1"
///   aad  = "<box>:<id>" for a mail, "<box>:<id>:<n>" for its attachment number n
enum SealedMail {
    static let suite = HPKE.Ciphersuite(kem: .Curve25519_HKDF_SHA256, kdf: .HKDF_SHA256, aead: .AES_GCM_256)
    static let info = Data("shoebox-mail-v1".utf8)

    /// Opens one sealed record. Throws if the key, the aad or any byte is wrong.
    static func open(enc: Data, ct: Data, aad: String, with key: Curve25519.KeyAgreement.PrivateKey) throws -> Data {
        var recipient = try HPKE.Recipient(privateKey: key, ciphersuite: suite, info: info, encapsulatedKey: enc)
        return try recipient.open(ct, authenticating: Data(aad.utf8))
    }

    /// The same, from the base64 the relay stores. Nil when anything fails: a record this phone cannot open is not an
    /// error to show, only something to count.
    static func openBase64(enc: String?, ct: String?, aad: String, with key: Curve25519.KeyAgreement.PrivateKey) -> Data? {
        guard let enc, let ct, let e = Data(base64Encoded: enc), let c = Data(base64Encoded: ct) else { return nil }
        return try? open(enc: e, ct: c, aad: aad, with: key)
    }

    /// What the relay sealed for one mail.
    struct Opened: Decodable {
        var from: String?
        var fromName: String?
        var subject: String?
        var text: String?
        var links: [String]?
        var attachments: [Inbox.Attachment]?
    }

    /// Seals data to a public key. The relay does this; the phone does it only in tests, to make records of its own.
    static func seal(_ data: Data, aad: String, to publicKey: Curve25519.KeyAgreement.PublicKey) throws -> (enc: Data, ct: Data) {
        var sender = try HPKE.Sender(recipientKey: publicKey, ciphersuite: suite, info: info)
        let ct = try sender.seal(data, authenticating: Data(aad.utf8))
        return (sender.encapsulatedKey, ct)
    }
}
