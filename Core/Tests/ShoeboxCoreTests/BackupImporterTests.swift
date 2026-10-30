import Foundation
import Testing
@testable import ShoeboxCore

struct BackupImporterTests {
    // Wed Nov 4 2026, 2:00 PM in New York: the same "now" as the spec's planner examples.
    static let now = Date(timeIntervalSince1970: 1_793_818_800)
    static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }

    func fixture() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "backup-v2", withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func run(existing: Set<String> = []) throws -> BackupImporter.Result {
        try BackupImporter.read(fixture(), options: .init(now: Self.now, calendar: Self.calendar, existingOldIds: existing))
    }

    func save(_ r: BackupImporter.Result, _ old: String) throws -> SaveValue {
        try #require(r.saves.first { $0.oldId == old })
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: BackupImporter.Failure.notABackup) { try BackupImporter.read(Data("{\"app\":\"other\",\"items\":[]}".utf8)) }
        #expect(throws: BackupImporter.Failure.notABackup) { try BackupImporter.read(Data("not json".utf8)) }
        #expect(throws: BackupImporter.Failure.notABackup) { try BackupImporter.read(Data("{\"app\":\"edition\"}".utf8)) }
    }

    @Test func countsAndReport() throws {
        let r = try run()
        #expect(r.report.saves == 12)
        #expect(r.report.samplesSkipped == 1)
        #expect(r.report.files == 2)
        #expect(r.report.missingFiles == 1)
        #expect(r.report.emailAddress)
        #expect(r.report.aiSignUp)
    }

    @Test func statusMapping() throws {
        let r = try run()
        #expect(try save(r, "a1").status == .unplanned)
        #expect(try save(r, "a2").status == .unplanned)
        #expect(try save(r, "a3").status == .quiet)       // queued, 40 days untouched
        #expect(try save(r, "a4").status == .planned)     // aside with a future date
        #expect(try save(r, "a5").status == .done)
        #expect(try save(r, "a6").status == .dropped)
        #expect(try save(r, "a7").status == .quiet)       // washed out
        #expect(try save(r, "a9").status == .dropped)     // old suggestion
        #expect(try save(r, "a11").status == .quiet)      // school date passed
    }

    @Test func fieldsCarryOver() throws {
        let r = try run()
        let a1 = try save(r, "a1")
        #expect(a1.reason == "try this weekend")
        #expect(a1.reasonSource == .imported)
        #expect(a1.tags == ["baking"])
        #expect(a1.source == .import)
        let a8 = try save(r, "a8")
        #expect(a8.kind == .file)                         // old text kind
        #expect(a8.edited.contains(.title))
    }

    @Test func asideBecomesAnIssueMoment() throws {
        let r = try run()
        let a4 = try save(r, "a4")
        let m = try #require(r.moments.first { $0.saveId == a4.id })
        #expect(m.surface == .issue)
        let c = Self.calendar.dateComponents([.weekday, .hour, .minute], from: m.start)
        #expect(c.weekday == 6 && c.hour == 7 && c.minute == 0)   // Friday Nov 6, 7:00 AM

        let a13 = try save(r, "a13")                              // date passed: next Issue
        let m2 = try #require(r.moments.first { $0.saveId == a13.id })
        let c2 = Self.calendar.dateComponents([.day, .hour], from: m2.start)
        #expect(c2.day == 5 && c2.hour == 7)                      // Thursday Nov 5, 7:00 AM
    }

    @Test func filesAndEvents() throws {
        let r = try run()
        let a4 = try save(r, "a4")
        let files = r.attachments.filter { $0.saveId == a4.id }
        #expect(Set(files.map(\.role)) == [.original, .thumbnail])
        #expect(files.allSatisfy { $0.fileName.hasSuffix(".png") && $0.sha256.count == 64 && r.fileData[$0.id] != nil })
        let a5 = try save(r, "a5")
        #expect(r.events.filter { $0.saveId == a5.id }.map(\.type) == [.done])
    }

    @Test func settingsCarryOver() throws {
        let s = try run().settings
        #expect(s.inboxKey == "k123")
        #expect(s.statsOff)
        #expect(s.school?.child == "Alex")
        #expect(s.school?.days == [1, 5])
    }

    @Test func importingTwiceAddsNothing() throws {
        let first = try run()
        let again = try run(existing: Set(first.saves.compactMap(\.oldId)))
        #expect(again.saves.isEmpty)
        #expect(again.report.alreadyHere == 12)
    }
}
