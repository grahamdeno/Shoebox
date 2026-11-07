import CryptoKit
import XCTest
@testable import Shoebox

/// An in-memory stand-in for the Keychain. The real Keychain can refuse under CODE_SIGNING_ALLOWED=NO.
final class MemorySecretStore: SecretStore {
    var items: [String: Data] = [:]
    var failWrites = false
    var corruptWrites = false
    /// Reads fail (the phone is locked, the Keychain is busy) for these accounts.
    var failReads: Set<String> = []
    func read(_ account: String) -> SecretRead {
        if failReads.contains(account) { return .failed }
        return items[account].map(SecretRead.found) ?? .missing
    }
    func add(_ data: Data, account: String) -> Bool {
        if failWrites || items[account] != nil { return false }
        items[account] = corruptWrites ? Data("other".utf8) : data
        return true
    }
    func write(_ data: Data, account: String) -> Bool {
        if failWrites { return false }
        items[account] = corruptWrites ? Data("other".utf8) : data
        return true
    }
    func remove(_ account: String) { items[account] = nil }
}

/// D-5 and D-6: the mailbox secret lives in the Keychain, moves there safely, and Delete everything finishes.
@MainActor
final class MailboxKeysTests: XCTestCase {
    private var store: MemorySecretStore!
    private var defaults: UserDefaults!
    private var saved: SecretStore!

    override func setUp() {
        saved = MailboxKeys.store
        store = MemorySecretStore()
        MailboxKeys.store = store
        defaults = UserDefaults(suiteName: "test.mailbox.\(UUID().uuidString)")!
    }
    override func tearDown() { MailboxKeys.store = saved }

    private let key = "sb-0123456789abcdef0123456789abcdef01234567"

    func testMigrationMovesTheKeyAndRemovesThePlainCopy() {
        defaults.set(key, forKey: "inboxKey")
        MailboxKeys.migrate(defaults: defaults)
        XCTAssertEqual(MailboxKeys.secret(), key)
        XCTAssertNil(defaults.string(forKey: "inboxKey"))
    }

    func testAFailedWriteLeavesThePlainCopy() {
        defaults.set(key, forKey: "inboxKey")
        store.failWrites = true
        MailboxKeys.migrate(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "inboxKey"), key)
    }

    func testAReadBackThatDoesNotMatchLeavesThePlainCopy() {
        defaults.set(key, forKey: "inboxKey")
        store.corruptWrites = true
        MailboxKeys.migrate(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "inboxKey"), key)
    }

    func testAKeyAlreadyInTheKeychainWins() {
        store.items["secret"] = Data("sb-fromanotherphone".utf8)
        defaults.set(key, forKey: "inboxKey")
        MailboxKeys.migrate(defaults: defaults)
        XCTAssertEqual(MailboxKeys.secret(), "sb-fromanotherphone")
        XCTAssertNil(defaults.string(forKey: "inboxKey"))
    }

    func testRestoreFillsAnEmptyKeychainOnly() {
        MailboxKeys.restoreIfEmpty(key)
        XCTAssertEqual(MailboxKeys.secret(), key)
        MailboxKeys.restoreIfEmpty("sb-other")
        XCTAssertEqual(MailboxKeys.secret(), key, "a restore never replaces a key")
    }

    func testRestoreDoesNotBringBackAMailboxThatIsBeingDeleted() {
        store.items["pendingDelete"] = Data(key.utf8)
        MailboxKeys.restoreIfEmpty(key)
        XCTAssertNil(MailboxKeys.secret())
    }

    func testTheSecretIsMadeOnceAndKept() throws {
        let a = try XCTUnwrap(MailboxKeys.secretMakingOne())
        XCTAssertTrue(a.hasPrefix("sb-"))
        XCTAssertEqual(a.count, 43)
        XCTAssertEqual(MailboxKeys.secretMakingOne(), a)
    }

    func testABackupNeverContainsTheKey() throws {
        store.items["secret"] = Data(key.utf8)
        let container = try Store.make(inMemory: true)
        let data = try XCTUnwrap(Backups.export(container.mainContext))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(key))
    }

    func testBeginDeleteMovesTheSecretAndRemovesTheKeys() {
        _ = MailboxKeys.secretMakingOne()
        _ = MailboxKeys.sealingKey()
        let secret = MailboxKeys.secret()
        XCTAssertTrue(MailboxKeys.beginDelete())
        XCTAssertNil(MailboxKeys.secret())
        XCTAssertNil(store.items["seal"])
        XCTAssertEqual(MailboxKeys.pendingDelete(), secret)
    }

    func testBeginDeleteChangesNothingIfThePendingCopyCannotBeStored() {
        _ = MailboxKeys.secretMakingOne()
        store.failWrites = true
        XCTAssertFalse(MailboxKeys.beginDelete())
        XCTAssertNotNil(MailboxKeys.secret())
    }

    private func pend() -> String {
        _ = MailboxKeys.secretMakingOne()
        MailboxKeys.beginDelete()
        return MailboxKeys.pendingDelete()!
    }

    private let ok = Data(#"{"ok":true,"mail":0}"#.utf8)
    private let refused = Data(#"{"error":{"message":"No inbox key."}}"#.utf8)

    func testOfflineKeepsThePendingDelete() async {
        let secret = pend()
        let done = await Inbox.finishPendingDelete(send: { _ in (nil, nil) })
        XCTAssertFalse(done)
        XCTAssertEqual(MailboxKeys.pendingDelete(), secret)
    }

    func testA500KeepsItAnd200ClearsIt() async {
        _ = pend()
        let ok = self.ok
        var finished = await Inbox.finishPendingDelete(send: { _ in (500, nil) })
        XCTAssertFalse(finished)
        XCTAssertNotNil(MailboxKeys.pendingDelete())
        finished = await Inbox.finishPendingDelete(send: { _ in (200, ok) })
        XCTAssertTrue(finished)
        XCTAssertNil(MailboxKeys.pendingDelete())
    }

    func testA401AlsoEndsIt() async {
        _ = pend()
        let refused = self.refused
        let finished = await Inbox.finishPendingDelete(send: { _ in (401, refused) })
        XCTAssertTrue(finished)
        XCTAssertNil(MailboxKeys.pendingDelete())
    }

    func testTheRequestCarriesThePendingSecret() async {
        let secret = pend()
        var sent: URLRequest?
        let ok = self.ok
        _ = await Inbox.finishPendingDelete(send: { sent = $0; return (200, ok) })
        XCTAssertEqual(sent?.url?.path.hasSuffix("me/delete"), true)
        XCTAssertTrue(sent?.allHTTPHeaderFields?.values.contains(where: { $0.contains(secret) }) ?? false)
    }

    // Fix 4: only the relay's own answer ends the retries.

    func testA200ThatIsNotTheRelaysAnswerKeepsThePendingDelete() async {
        _ = pend()
        let portal = Data("<html>Sign in to Hotel Wi-Fi</html>".utf8)
        var finished = await Inbox.finishPendingDelete(send: { _ in (200, portal) })
        XCTAssertFalse(finished, "a Wi-Fi sign-in page must not end the retries")
        finished = await Inbox.finishPendingDelete(send: { _ in (200, Data(#"{"ok":false}"#.utf8)) })
        XCTAssertFalse(finished)
        finished = await Inbox.finishPendingDelete(send: { _ in (200, nil) })
        XCTAssertFalse(finished)
        XCTAssertNotNil(MailboxKeys.pendingDelete())
    }

    func testA401ThatIsNotTheRelaysAnswerKeepsThePendingDelete() async {
        _ = pend()
        let finished = await Inbox.finishPendingDelete(send: { _ in (401, Data("Unauthorized".utf8)) })
        XCTAssertFalse(finished)
        XCTAssertNotNil(MailboxKeys.pendingDelete())
    }

    func testNothingPendingMeansNothingToDo() async {
        var called = false
        let done = await Inbox.finishPendingDelete(send: { _ in called = true; return (200, nil) })
        XCTAssertTrue(done)
        XCTAssertFalse(called)
    }

    // Fix 1: a key is made only when the Keychain says there is none.

    func testAFailedReadNeverReplacesTheSealingKey() {
        let real = Curve25519.KeyAgreement.PrivateKey()
        store.items["seal"] = real.rawRepresentation
        store.failReads = ["seal"]
        XCTAssertNil(MailboxKeys.sealingKey())
        XCTAssertNil(MailboxKeys.sealingPublicKey())
        guard case .failed = MailboxKeys.sealingKeyState() else { return XCTFail("a failed read is not a missing key") }
        XCTAssertEqual(store.items["seal"], real.rawRepresentation, "the real key is untouched")
        store.failReads = []
        XCTAssertEqual(MailboxKeys.sealingKey()?.rawRepresentation, real.rawRepresentation)
    }

    func testBytesThatAreNotAKeyAreNeverReplaced() {
        store.items["seal"] = Data([1, 2, 3])
        XCTAssertNil(MailboxKeys.sealingKey())
        XCTAssertEqual(store.items["seal"], Data([1, 2, 3]))
    }

    func testAFailedReadNeverReplacesTheSecret() {
        store.items["secret"] = Data(key.utf8)
        store.failReads = ["secret"]
        XCTAssertNil(MailboxKeys.secretMakingOne())
        store.failReads = []
        XCTAssertEqual(MailboxKeys.secret(), key)
    }

    func testAKeyThatArrivedInBetweenWins() {
        // Missing on the first read, then iCloud Keychain delivers one before the add: the add fails, that one is used.
        final class ArrivesLate: SecretStore {
            let inner = MemorySecretStore()
            let arriving: Data
            var reads = 0
            init(_ arriving: Data) { self.arriving = arriving }
            func read(_ account: String) -> SecretRead {
                reads += 1
                if reads == 2 { inner.items[account] = arriving }
                return inner.read(account)
            }
            func add(_ data: Data, account: String) -> Bool {
                if inner.items[account] == nil { inner.items[account] = arriving }
                return inner.add(data, account: account)
            }
            func write(_ data: Data, account: String) -> Bool { inner.write(data, account: account) }
            func remove(_ account: String) { inner.remove(account) }
        }
        let real = Curve25519.KeyAgreement.PrivateKey()
        MailboxKeys.store = ArrivesLate(real.rawRepresentation)
        XCTAssertEqual(MailboxKeys.sealingKey()?.rawRepresentation, real.rawRepresentation)
    }

    func testAMissingKeyIsMadeOnce() {
        let a = MailboxKeys.sealingKey()
        XCTAssertNotNil(a)
        XCTAssertEqual(MailboxKeys.sealingKey()?.rawRepresentation, a?.rawRepresentation)
    }

    func testMigrationWaitsWhenTheKeychainCantBeRead() {
        defaults.set(key, forKey: "inboxKey")
        store.failReads = ["secret"]
        MailboxKeys.migrate(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "inboxKey"), key)
        XCTAssertNil(store.items["secret"])
    }

    func testDeleteChangesNothingWhenTheKeychainCantBeRead() {
        store.items["secret"] = Data(key.utf8)
        store.failReads = ["secret"]
        XCTAssertFalse(MailboxKeys.beginDelete())
        XCTAssertEqual(store.items["secret"], Data(key.utf8))
        XCTAssertNil(store.items["pendingDelete"])
    }

    func testRestoreWaitsWhenTheKeychainCantBeRead() {
        store.failReads = ["secret"]
        MailboxKeys.restoreIfEmpty(key)
        XCTAssertNil(store.items["secret"])
    }

    // Fix 2: the relay's key is replaced only when nothing can be lost.

    func testSealingStep() {
        let now = Date()
        let step = { (held: String?, mine: String?, since: Date?, force: Bool) in
            Inbox.sealingStep(held: held, mine: mine, mismatchSince: since, now: now, force: force)
        }
        XCTAssertEqual(step("a", "a", nil, false), .ready)
        XCTAssertEqual(step(nil, "a", nil, false), .register, "the relay holds no key: nothing is sealed to anything")
        XCTAssertEqual(step(nil, nil, nil, false), .register)
        XCTAssertEqual(step("a", "b", nil, false), .wait, "another key: this phone's may still be on its way")
        XCTAssertEqual(step("a", nil, nil, false), .wait, "no key here yet: never make one over the one the relay holds")
        XCTAssertEqual(step("a", "b", now.addingTimeInterval(-3_600), false), .wait)
        XCTAssertEqual(step("a", "b", now.addingTimeInterval(-Inbox.sealingGrace), false), .register, "a day later")
        XCTAssertEqual(step("a", nil, nil, true), .register, "Restore purchases")
        XCTAssertEqual(step("a", "a", nil, true), .ready)
    }

    func testWaitingMakesNoKeyAndStartsTheClock() async {
        let d = AppGroup.defaults
        let saved = (d.object(forKey: "sealMismatchSince"), d.bool(forKey: "sealingRegistered"))
        defer { d.set(saved.0, forKey: "sealMismatchSince"); d.set(saved.1, forKey: "sealingRegistered") }
        Prefs.sealMismatchSince = nil
        let other = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        let now = Date()
        let key = await Inbox.settleSealing(held: other, hasAddress: true, key: self.key, force: false, now: now)
        XCTAssertNil(key)
        XCTAssertNil(store.items["seal"], "no key is made while the relay holds another")
        XCTAssertEqual(Prefs.sealMismatchSince, now)
        XCTAssertFalse(Prefs.sealingRegistered)
        // A later look keeps the first time, so the day is counted from when the mismatch was first seen.
        _ = await Inbox.settleSealing(held: other, hasAddress: true, key: self.key, force: false, now: now.addingTimeInterval(60))
        XCTAssertEqual(Prefs.sealMismatchSince, now)
    }

    func testTheRelaysOwnKeyClearsTheClock() async {
        let d = AppGroup.defaults
        let saved = (d.object(forKey: "sealMismatchSince"), d.bool(forKey: "sealingRegistered"))
        defer { d.set(saved.0, forKey: "sealMismatchSince"); d.set(saved.1, forKey: "sealingRegistered") }
        let mine = Curve25519.KeyAgreement.PrivateKey()
        store.items["seal"] = mine.rawRepresentation
        Prefs.sealMismatchSince = Date(timeIntervalSince1970: 0)
        let key = await Inbox.settleSealing(held: MailboxKeys.publicText(mine), hasAddress: true, key: self.key, force: false)
        XCTAssertEqual(key?.rawRepresentation, mine.rawRepresentation)
        XCTAssertNil(Prefs.sealMismatchSince)
        XCTAssertTrue(Prefs.sealingRegistered)
    }

    func testBoxIDMatchesTheRelaysDerivation() {
        // sha256("inbox:" + secret), first 20 hex characters: the same rule as relay/app/worker.js.
        let digest = SHA256.hash(data: Data("inbox:\(key)".utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(MailboxKeys.boxID(for: key), String(digest.prefix(20)))
        XCTAssertEqual(MailboxKeys.boxID(for: key).count, 20)
    }

    func testTheTesterCodeIsKeptTrimmedAndForgottenByDeleteEverything() {
        XCTAssertNil(MailboxKeys.testerCode())
        MailboxKeys.setTesterCode("  plum-otter-4821 \n")
        XCTAssertEqual(MailboxKeys.testerCode(), "plum-otter-4821")
        _ = MailboxKeys.secretMakingOne()
        XCTAssertTrue(MailboxKeys.beginDelete())
        XCTAssertNil(MailboxKeys.testerCode())
        MailboxKeys.setTesterCode("plum-otter-4821")
        MailboxKeys.setTesterCode("")
        XCTAssertNil(MailboxKeys.testerCode())
    }
}
