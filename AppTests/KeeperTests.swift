import Testing
import Foundation
import SwiftData
@testable import Shoebox
import ShoeboxCore

@MainActor
struct KeeperTests {
    func keeper() -> Keeper {
        let k = Keeper(context: ModelContext(StoreBox.memory()))
        k.now = { Date(timeIntervalSince1970: 1_793_818_800) }   // Wed Nov 4 2026, 2:00 PM New York
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!
        k.calendar = c
        return k
    }

    @Test func keepPlansOneMoment() {
        let k = keeper()
        let (s, o) = k.keep(Detection.Draft(kind: .link, title: "Bread", url: "https://example.com"), reason: "This weekend",
                            reasonSource: .typed, source: .share)
        #expect(s.status == .planned)
        #expect(k.nextMoment(for: s)?.start == o.moment.start)
        #expect(k.openMoments().count == 1)
    }

    @Test func twoPassesGoQuiet() {
        let k = keeper()
        let (s, _) = k.keep(Detection.Draft(kind: .note, title: "Note"), reason: "Tomorrow", reasonSource: .typed, source: .paste)
        k.pass(s, events: [])
        #expect(s.status == .planned)
        k.pass(s, events: [])
        #expect(s.status == .quiet)
        #expect(s.nextMomentId == nil)
    }

    @Test func laterIsNotAPass() {
        let k = keeper()
        let (s, _) = k.keep(Detection.Draft(kind: .note, title: "Note"), reason: "", reasonSource: .none, source: .paste)
        k.later(s, .tonight, events: [])
        k.later(s, .nextWeek, events: [])
        #expect(s.passes == 0)
        #expect(s.status == .planned)
    }

    @Test func bringBackResets() {
        let k = keeper()
        let (s, _) = k.keep(Detection.Draft(kind: .note, title: "Note"), reason: "", reasonSource: .none, source: .paste)
        k.pass(s, events: []); k.pass(s, events: [])
        k.bringBack(s, .youChoose, events: [])
        #expect(s.status == .planned && s.passes == 0)
    }

    @Test func deleteLeavesATombstone() {
        let k = keeper()
        let (s, _) = k.keep(Detection.Draft(kind: .note, title: "Secret", text: "private"), reason: "x", reasonSource: .typed, source: .paste)
        k.delete(s)
        #expect(s.deletedAt != nil && s.title.isEmpty && s.text == nil)
        #expect(k.allSaves().isEmpty)
    }

    @Test func oldBackupImportsOnce() throws {
        let k = keeper()
        let json = """
        {"app":"edition","version":2,"items":[{"id":"x1","kind":"link","title":"T","url":"https://a.com","why":"Next week","status":"inbox","created":1793700000000}],"files":[],"settings":{}}
        """
        let first = try ImportService.importData(Data(json.utf8), keeper: k)
        #expect(first.count == 1)
        let again = try ImportService.importData(Data(json.utf8), keeper: k)
        #expect(again.count == 0)
        #expect(k.allSaves().count == 1)
    }
}
