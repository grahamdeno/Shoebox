import SwiftData
import XCTest
@testable import Shoebox

/// D-1: the store has a version, opens stores made before versions existed, and never crashes or deletes on a failure.
final class StoreTests: XCTestCase {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "shoebox-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    func testTheSchemaNamesTheSaveModelAtVersionOne() {
        XCTAssertEqual(ShoeboxSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(ShoeboxSchemaV1.models.count, 1)
        XCTAssertEqual(ShoeboxMigrationPlan.schemas.count, 1)
        XCTAssertTrue(ShoeboxMigrationPlan.stages.isEmpty)
    }

    @MainActor
    func testAStoreMadeBeforeVersionsStillOpensWithItsPosts() throws {
        let url = try tempDir().appending(path: "Shoebox.store")
        do {
            // How every earlier build made the store: no schema version, no plan.
            let old = try ModelContainer(for: Save.self, configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
            old.mainContext.insert(Save(title: "Keep me", note: "for later", origin: "test", kind: .note))
            try old.mainContext.save()
        }
        let reopened = try Store.make(at: url)
        let saves = try reopened.mainContext.fetch(FetchDescriptor<Save>())
        XCTAssertEqual(saves.map(\.title), ["Keep me"])
        XCTAssertEqual(saves.first?.note, "for later")
    }

    @MainActor
    func testAVersionedStoreReopensWithItsPosts() throws {
        let url = try tempDir().appending(path: "Shoebox.store")
        do {
            let first = try Store.make(at: url)
            first.mainContext.insert(Save(title: "One", kind: .note))
            first.mainContext.insert(Save(title: "Two", kind: .link))
            try first.mainContext.save()
        }
        let second = try Store.make(at: url)
        let titles = try second.mainContext.fetch(FetchDescriptor<Save>()).map(\.title).sorted()
        XCTAssertEqual(titles, ["One", "Two"])
    }

    func testSettingAsideCopiesBeforeItRemoves() throws {
        let fm = FileManager.default
        let group = try tempDir(), docs = try tempDir()
        for name in ["Shoebox.store", "Shoebox.store-wal", "Shoebox.store-shm", "other.txt"] {
            try Data(name.utf8).write(to: group.appending(path: name))
        }
        let support = group.appending(path: ".Shoebox_SUPPORT/_EXTERNAL_DATA")
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        try Data("picture".utf8).write(to: support.appending(path: "abc"))

        let dest = try Store.setAside(from: group, into: docs, now: Date(timeIntervalSince1970: 1_793_595_660))
        XCTAssertTrue(dest.lastPathComponent.hasPrefix("Recovered 2026-"))
        for name in ["Shoebox.store", "Shoebox.store-wal", "Shoebox.store-shm"] {
            XCTAssertTrue(fm.fileExists(atPath: dest.appending(path: name).path), "\(name) copied")
            XCTAssertFalse(fm.fileExists(atPath: group.appending(path: name).path), "\(name) removed from the group")
        }
        XCTAssertEqual(try String(contentsOf: dest.appending(path: ".Shoebox_SUPPORT/_EXTERNAL_DATA/abc"), encoding: .utf8), "picture")
        XCTAssertFalse(fm.fileExists(atPath: group.appending(path: ".Shoebox_SUPPORT").path))
        XCTAssertTrue(fm.fileExists(atPath: group.appending(path: "other.txt").path), "unrelated files are left alone")
    }

    func testNothingIsRemovedWhenTheCopyCannotBeMade() throws {
        let fm = FileManager.default
        let group = try tempDir(), docs = try tempDir()
        try Data("db".utf8).write(to: group.appending(path: "Shoebox.store"))
        // The place for the copy is a file, so the folder cannot be made.
        let blocked = docs.appending(path: "blocked")
        try Data("x".utf8).write(to: blocked)
        XCTAssertThrowsError(try Store.setAside(from: group, into: blocked))
        XCTAssertTrue(fm.fileExists(atPath: group.appending(path: "Shoebox.store").path), "the store is untouched")
    }
}
