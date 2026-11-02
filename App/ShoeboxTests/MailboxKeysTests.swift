import CryptoKit
import XCTest
@testable import Shoebox

/// An in-memory stand-in for the Keychain. The real Keychain can refuse under CODE_SIGNING_ALLOWED=NO.
final class MemorySecretStore: SecretStore {
    var items: [String: Data] = [:]
    var failWrites = false
    var corruptWrites = false
    func read(_ account: String) -> Data? { items[account] }
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

    func testTheSecretIsMadeOnceAndKept() {
        let a = MailboxKeys.secretMakingOne()
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

    func testOfflineKeepsThePendingDelete() async {
        let secret = pend()
        let done = await Inbox.finishPendingDelete(send: { _ in nil })
        XCTAssertFalse(done)
        XCTAssertEqual(MailboxKeys.pendingDelete(), secret)
    }

    func testA500KeepsItAnd200ClearsIt() async {
        _ = pend()
        var finished = await Inbox.finishPendingDelete(send: { _ in 500 })
        XCTAssertFalse(finished)
        XCTAssertNotNil(MailboxKeys.pendingDelete())
        finished = await Inbox.finishPendingDelete(send: { _ in 200 })
        XCTAssertTrue(finished)
        XCTAssertNil(MailboxKeys.pendingDelete())
    }

    func testA401AlsoEndsIt() async {
        _ = pend()
        let finished = await Inbox.finishPendingDelete(send: { _ in 401 })
        XCTAssertTrue(finished)
        XCTAssertNil(MailboxKeys.pendingDelete())
    }

    func testTheRequestCarriesThePendingSecret() async {
        let secret = pend()
        var sent: URLRequest?
        _ = await Inbox.finishPendingDelete(send: { sent = $0; return 200 })
        XCTAssertEqual(sent?.url?.path.hasSuffix("me/delete"), true)
        XCTAssertTrue(sent?.allHTTPHeaderFields?.values.contains(where: { $0.contains(secret) }) ?? false)
    }

    func testNothingPendingMeansNothingToDo() async {
        var called = false
        let done = await Inbox.finishPendingDelete(send: { _ in called = true; return 200 })
        XCTAssertTrue(done)
        XCTAssertFalse(called)
    }

    func testBoxIDMatchesTheRelaysDerivation() {
        // sha256("inbox:" + secret), first 20 hex characters: the same rule as relay/app/worker.js.
        let digest = SHA256.hash(data: Data("inbox:\(key)".utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(MailboxKeys.boxID(for: key), String(digest.prefix(20)))
        XCTAssertEqual(MailboxKeys.boxID(for: key).count, 20)
    }
}
