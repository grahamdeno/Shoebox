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
///
/// The one rule that keeps mail safe: a key is made only when the Keychain says, plainly, that there is none. A read
/// that fails for any other reason (the phone is locked, the Keychain is busy) makes nothing and replaces nothing.
/// Making a key over a real one would lose it on every phone, because the new one syncs through iCloud Keychain.
enum SecretRead: Equatable {
    case found(Data)
    case missing
    case failed
}

protocol SecretStore {
    func read(_ account: String) -> SecretRead
    /// Adds a new item. False, changing nothing, if one is already there or the Keychain refused.
    func add(_ data: Data, account: String) -> Bool
    /// Replaces an item, or adds it. Only for values meant to be overwritten (the pending delete).
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

    func read(_ account: String) -> SecretRead {
        var query = match(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &out) {
        case errSecSuccess: return (out as? Data).map(SecretRead.found) ?? .failed
        case errSecItemNotFound: return .missing
        default: return .failed
        }
    }

    func add(_ data: Data, account: String) -> Bool {
        var item = match(account)
        item[kSecAttrSynchronizable as String] = true
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        item[kSecValueData as String] = data
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    func write(_ data: Data, account: String) -> Bool {
        let status = SecItemUpdate(match(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        return status == errSecItemNotFound && add(data, account: account)
    }

    func remove(_ account: String) {
        SecItemDelete(match(account) as CFDictionary)
    }
}

/// The sealing key as the Keychain holds it.
enum SealState {
    case found(Curve25519.KeyAgreement.PrivateKey)
    case missing
    /// The Keychain could not be read, or holds bytes that are not a key. Never replaced: it may be the real one.
    case failed
}

enum MailboxKeys {
    /// Swapped in by tests.
    static var store: SecretStore = KeychainSecretStore()

    private enum Account { static let secret = "secret", seal = "seal", pendingDelete = "pendingDelete", testerCode = "testerCode" }

    private static func text(_ read: SecretRead) -> String? {
        guard case .found(let data) = read, let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }

    // MARK: The mailbox secret

    /// The secret, or nil when there is none (never asked for an address, or Delete everything took it) or the
    /// Keychain can't be read right now.
    static func secret() -> String? { text(store.read(Account.secret)) }

    /// The secret, made on first need. Nil when the Keychain can't be read or written: a second secret is never made
    /// over one that is there.
    static func secretMakingOne() -> String? {
        switch store.read(Account.secret) {
        case .found: return secret()
        case .failed: return nil
        case .missing:
            let made = "sb-" + String((0..<4).map { _ in UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() }.joined().prefix(40))
            if store.add(Data(made.utf8), account: Account.secret) { return made }
            // One arrived in between (through iCloud Keychain): that one wins.
            return secret()
        }
    }

    /// D-5, on every launch. The key used to live in the App Group's plain defaults. Move it: add it to the Keychain,
    /// read it back, compare, and only then remove the plain copy. Anything else leaves the plain copy where it is and
    /// the next launch tries again. If the Keychain already has a key (it came from another phone through iCloud
    /// Keychain), that key wins and the stale plain copy is removed.
    static func migrate(defaults: UserDefaults = AppGroup.defaults) {
        guard let plain = defaults.string(forKey: "inboxKey"), !plain.isEmpty else { return }
        switch store.read(Account.secret) {
        case .failed: return
        case .found:
            if secret() != nil { defaults.removeObject(forKey: "inboxKey") }
        case .missing:
            guard store.add(Data(plain.utf8), account: Account.secret), secret() == plain else { return }
            defaults.removeObject(forKey: "inboxKey")
        }
    }

    /// A key from a backup (or from Shoebox 1) fills an empty Keychain and nothing else. Never replaces one, and never
    /// brings back a mailbox that Delete everything is still removing.
    static func restoreIfEmpty(_ key: String?) {
        guard let key, !key.isEmpty,
              store.read(Account.pendingDelete) == .missing, store.read(Account.secret) == .missing else { return }
        _ = store.add(Data(key.utf8), account: Account.secret)
    }

    // MARK: The sealing key pair

    static func sealingKeyState() -> SealState {
        switch store.read(Account.seal) {
        case .found(let data):
            guard let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data) else { return .failed }
            return .found(key)
        case .missing: return .missing
        case .failed: return .failed
        }
    }

    /// The private key mail is sealed to, made when the Keychain says there is none. Nil when it can't be read or stored.
    static func sealingKey() -> Curve25519.KeyAgreement.PrivateKey? {
        switch sealingKeyState() {
        case .found(let key): return key
        case .failed: return nil
        case .missing:
            let made = Curve25519.KeyAgreement.PrivateKey()
            if store.add(made.rawRepresentation, account: Account.seal) { return made }
            if case .found(let key) = sealingKeyState() { return key }
            return nil
        }
    }

    /// Standard base64 of the public half's 32 bytes: what the relay is given.
    static func publicText(_ key: Curve25519.KeyAgreement.PrivateKey) -> String {
        key.publicKey.rawRepresentation.base64EncodedString()
    }

    /// The public half of the sealing key, made on first need (see `sealingKey`).
    static func sealingPublicKey() -> String? { sealingKey().map(publicText) }

    // MARK: The tester code (decided November 6)

    /// The tester code this phone was given, kept so the sealing key can be registered with it later. Typed in
    /// Settings › Email in TestFlight; the relay decides whether it is a real one.
    static func testerCode() -> String? { text(store.read(Account.testerCode)) }

    static func setTesterCode(_ code: String) {
        let clean = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { store.remove(Account.testerCode) } else { store.write(Data(clean.utf8), account: Account.testerCode) }
    }

    // MARK: Delete everything (D-6)

    /// The secret of a mailbox the relay has not yet confirmed deleted.
    static func pendingDelete() -> String? { text(store.read(Account.pendingDelete)) }

    /// Step 3 of Delete everything: the secret moves to `pendingDelete` and `secret` and `seal` go. From here the app
    /// has no mailbox. Returns false, changing nothing, if the Keychain can't be read or the pending copy can't be stored.
    @discardableResult
    static func beginDelete() -> Bool {
        switch store.read(Account.secret) {
        case .missing: return true
        case .failed: return false
        case .found: break
        }
        guard let current = secret(), store.write(Data(current.utf8), account: Account.pendingDelete),
              pendingDelete() == current else { return false }
        store.remove(Account.secret)
        store.remove(Account.seal)
        store.remove(Account.testerCode)
        return true
    }

    /// The relay confirmed: nothing is left to remember.
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
