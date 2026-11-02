import CryptoKit
import Foundation
import Security

/// What the phone holds for its mailbox (docs/design/identity-and-sealed-mail.md). Two secrets, both in the Keychain
/// and synced through iCloud Keychain so a new phone on the same Apple Account picks them up:
///
///   secret         the mailbox secret ("sb-" + 40 characters). Sent to the relay in a header; the relay keeps only a hash.
///   seal           the private half of the sealing key pair (X25519, 32 raw bytes). Mail is sealed to its public half.
///   pendingDelete  the secret of a mailbox that Delete everything is still removing from the relay.
///
/// Everything reads the secret through here, never from `Prefs`. The app only: the share extension never needs it.
protocol SecretStore {
    func read(_ account: String) -> Data?
    /// True only when the value is stored.
    @discardableResult func write(_ data: Data, account: String) -> Bool
    func remove(_ account: String)
}

/// The Keychain: generic passwords under one service, synchronizable, readable after the first unlock so background
/// work can use them while the phone is locked.
struct KeychainSecretStore: SecretStore {
    static let service = "com.grahamdeno.shoebox.mailbox"

    private func match(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: kSecAttrSynchronizableAny]
    }

    func read(_ account: String) -> Data? {
        var query = match(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    @discardableResult
    func write(_ data: Data, account: String) -> Bool {
        // Replace, so an item that was made synchronizable or not, in an earlier build, never lingers beside the new one.
        SecItemDelete(match(account) as CFDictionary)
        var item = match(account)
        item[kSecAttrSynchronizable as String] = true
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        item[kSecValueData as String] = data
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func remove(_ account: String) {
        SecItemDelete(match(account) as CFDictionary)
    }
}

enum MailboxKeys {
    /// Swapped in by tests.
    static var store: SecretStore = KeychainSecretStore()

    private enum Account { static let secret = "secret", seal = "seal", pendingDelete = "pendingDelete" }

    // If the Keychain refuses a write, the value lives here for this run, so a key made a moment ago is not made again
    // (which would be a different key). The next launch tries the Keychain again.
    private static var heldSecret: String?
    private static var heldSeal: Curve25519.KeyAgreement.PrivateKey?

    // MARK: The mailbox secret

    /// The secret, or nil when the phone has never asked for an address (or Delete everything took it away).
    static func secret() -> String? {
        if let data = store.read(Account.secret), let text = String(data: data, encoding: .utf8), !text.isEmpty { return text }
        return heldSecret
    }

    /// The secret, made on first need.
    static func secretMakingOne() -> String {
        if let have = secret() { return have }
        let made = "sb-" + String((0..<4).map { _ in UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() }.joined().prefix(40))
        if !store.write(Data(made.utf8), account: Account.secret) { heldSecret = made }
        return made
    }

    /// D-5, on every launch. The key used to live in the App Group's plain defaults. Move it: write it to the Keychain,
    /// read it back, compare, and only then remove the plain copy. A failed write leaves the plain copy where it is
    /// and the next launch tries again. If the Keychain already has a key (it came from another phone through iCloud
    /// Keychain), that key wins and the stale plain copy is removed.
    static func migrate(defaults: UserDefaults = AppGroup.defaults) {
        guard let plain = defaults.string(forKey: "inboxKey"), !plain.isEmpty else { return }
        if let kept = store.read(Account.secret).flatMap({ String(data: $0, encoding: .utf8) }), !kept.isEmpty {
            defaults.removeObject(forKey: "inboxKey")
            return
        }
        guard store.write(Data(plain.utf8), account: Account.secret),
              store.read(Account.secret).flatMap({ String(data: $0, encoding: .utf8) }) == plain else { return }
        defaults.removeObject(forKey: "inboxKey")
    }

    /// A key from a backup (or from Shoebox 1) fills an empty Keychain and nothing else. Never replaces one, and never
    /// brings back a mailbox that Delete everything is still removing.
    static func restoreIfEmpty(_ key: String?) {
        guard let key, !key.isEmpty, secret() == nil, pendingDelete() == nil else { return }
        if !store.write(Data(key.utf8), account: Account.secret) { heldSecret = key }
    }

    // MARK: The sealing key pair

    /// The private key mail is sealed to, made on first need.
    static func sealingKey() -> Curve25519.KeyAgreement.PrivateKey {
        if let data = store.read(Account.seal), let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data) { return key }
        if let held = heldSeal { return held }
        let made = Curve25519.KeyAgreement.PrivateKey()
        if !store.write(made.rawRepresentation, account: Account.seal) { heldSeal = made }
        return made
    }

    /// The public half, standard base64 of 32 bytes: what the relay is given.
    static func sealingPublicKey() -> String {
        sealingKey().publicKey.rawRepresentation.base64EncodedString()
    }

    // MARK: Delete everything (D-6)

    /// The secret of a mailbox the relay has not yet confirmed deleted.
    static func pendingDelete() -> String? {
        store.read(Account.pendingDelete).flatMap { String(data: $0, encoding: .utf8) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Step 3 of Delete everything: the secret moves to `pendingDelete` and `secret` and `seal` go. From here the app
    /// has no mailbox. Returns false, changing nothing, if the pending copy could not be stored.
    @discardableResult
    static func beginDelete() -> Bool {
        guard let current = secret() else { return true }
        guard store.write(Data(current.utf8), account: Account.pendingDelete) else { return false }
        store.remove(Account.secret)
        store.remove(Account.seal)
        heldSecret = nil
        heldSeal = nil
        return true
    }

    /// The relay said 200: nothing is left to remember.
    static func finishDelete() {
        store.remove(Account.pendingDelete)
    }

    // MARK: The relay's name for the mailbox

    /// The box id the relay derives from the secret: the first 20 hex characters of SHA-256("inbox:" + secret).
    /// It is part of what each sealed mail is bound to (the `aad`).
    static func boxID(for secret: String) -> String {
        let digest = SHA256.hash(data: Data("inbox:\(secret)".utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(20))
    }
}
