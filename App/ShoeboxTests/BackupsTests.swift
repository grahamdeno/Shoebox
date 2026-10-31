import XCTest
@testable import Shoebox

final class BackupsTests: XCTestCase {
    func testFindsShoebox1BackupNames() {
        XCTAssertEqual(Backups.oldBackupName("shoebox-backup-2026-10-01.json"), "shoebox-backup-2026-10-01.json")
    }

    func testFindsBackupsICloudHasNotDownloaded() {
        XCTAssertEqual(Backups.oldBackupName(".shoebox-backup-2026-10-01.json.icloud"), "shoebox-backup-2026-10-01.json")
    }

    func testIgnoresOtherFiles() {
        XCTAssertNil(Backups.oldBackupName("shoebox-native-backup-2026-10-01.json"))
        XCTAssertNil(Backups.oldBackupName("shoebox-before-delete-1.json"))
        XCTAssertNil(Backups.oldBackupName(".DS_Store"))
        XCTAssertNil(Backups.oldBackupName("shoebox-backup-2026-10-01.json.tmp"))
    }

    func testReadsTheNewestBackupInAFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("old".utf8).write(to: dir.appending(path: "shoebox-backup-2026-09-01.json"))
        try Data("new".utf8).write(to: dir.appending(path: "shoebox-backup-2026-10-01.json"))
        try Data("mine".utf8).write(to: dir.appending(path: "shoebox-native-backup-2026-10-02.json"))
        XCTAssertEqual(Backups.readNewestOldBackup(in: [dir]).map { String(decoding: $0, as: UTF8.self) }, "new")
    }
}
