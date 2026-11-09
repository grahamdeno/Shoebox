import XCTest

/// The journeys of the UX audit, in the order a person meets them (docs/audit/08-ux-audit.md, section 2).
/// Each one is a person doing one job, step by step. The record and pictures go to AUDIT_OUT for the review.
@MainActor
final class Journeys: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    // J1. First launch: four screens, then Today.
    func test01_FirstLaunch() {
        let a = Audit("J1-first-launch")
        defer { a.finish() }
        a.launch(["-screen", "welcome"])
        a.shot("welcome")
        a.accessibility("welcome")
        a.labels("welcome")
        a.check("welcome says the promise", a.text(containing: "It comes back to you").exists, severity: 2)
        a.tap("Start", a.app.buttons["Start"])
        a.pause(0.8)
        a.shot("save-from-anywhere")
        a.accessibility("save-from-anywhere")
        a.tap("Next", a.app.buttons["Next"])
        a.pause(0.8)
        a.shot("when-they-come-out")
        a.accessibility("when-they-come-out")
        // Not now: the notification question is the system's, and it is a person's own choice.
        a.tap("Not now", a.app.buttons["Not now"])
        a.pause(1)
        a.shot("three-moves")
        a.accessibility("three-moves")
        a.labels("three-moves")
        a.pause(3)
        a.shot("three-moves-later", note: "the looping picture a few seconds on")
        a.tap("Try it", a.app.buttons["Try it"])
        a.pause(1.5)
        a.shot("today-after-onboarding")
        a.expect("Today shows + New", a.app.buttons["Keep something new"])
        a.expect("Today shows the box", a.button(startingWith: "Your Shoebox"))
    }

    // J2. Today: the three moves and Undo, each one.
    func test02_TodayMoves() {
        let a = Audit("J2-today-moves")
        defer { a.finish() }
        a.launch()
        a.shot("today")
        a.accessibility("today")
        a.labels("today")
        let before = a.counter
        let boxBefore = a.boxCount
        a.check("Today shows where you are (x of y)", before != nil, severity: 2, detail: before ?? "no counter")

        // Tap opens.
        let t0 = Date()
        a.tapPost()
        let opened = a.app.buttons["Close"].waitForExistence(timeout: 3)
        a.timing("tap to opened", Date().timeIntervalSince(t0))
        a.check("a tap opens the post", opened, severity: 4)
        a.shot("opened")
        a.accessibility("opened")
        a.labels("opened")
        a.tap("Close", a.app.buttons["Close"])
        a.pause(1)
        a.check("Close goes back to Today", a.app.buttons["Keep something new"].waitForExistence(timeout: 3), severity: 4)

        // Flick up: Next.
        a.flickUp()
        a.pause(0.4)
        a.shot("after-flick-up")
        let undo = a.app.buttons["Undo"]
        a.check("flick up shows Undo", undo.waitForExistence(timeout: 2), severity: 3)
        a.labels("after-flick-up")
        a.check("the counter moved on", a.counter != before, severity: 3, detail: "\(before ?? "-") then \(a.counter ?? "-")")
        if undo.exists { undo.tap(); a.pause(0.8) }
        a.shot("after-undo-next")
        a.check("Undo brings the post back", a.counter == before, severity: 4, detail: "\(before ?? "-") then \(a.counter ?? "-")")

        // Pull down: Put away.
        a.pullDown()
        a.pause(0.5)
        a.shot("after-pull-down")
        a.check("pull down shows Put away and Undo", a.text(containing: "Put away").exists && undo.waitForExistence(timeout: 2), severity: 3)
        a.check("the box count did not grow on Put away", (a.boxCount ?? 0) <= (boxBefore ?? 0), severity: 2,
                detail: "\(boxBefore ?? -1) then \(a.boxCount ?? -1)")
        if undo.exists { undo.tap(); a.pause(0.8) }
        a.check("Undo brings it back after Put away", a.counter == before, severity: 4, detail: "\(before ?? "-") then \(a.counter ?? "-")")

        // A short drag springs back and changes nothing.
        let p = a.app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        p.press(forDuration: 0.05, thenDragTo: a.app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        a.pause(0.8)
        a.check("a short drag changes nothing", a.counter == before && !a.app.buttons["Undo"].exists, severity: 3)

        // Swipe left: Delete shows beside the post, and only a tap on it deletes (with Undo).
        a.app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.45))
            .press(forDuration: 0.05, thenDragTo: a.app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.45)))
        a.pause(0.6)
        let del = a.app.buttons["today.delete"]
        a.check("swipe left shows Delete", del.waitForExistence(timeout: 2), severity: 3)
        a.shot("swiped-left")
        a.check("the swipe alone deletes nothing", a.counter == before && !undo.exists, severity: 4)
        if del.exists { del.tap(); a.pause(0.6) }
        a.check("a tap on Delete deletes, with Undo", a.text(containing: "Deleted").exists && undo.waitForExistence(timeout: 2), severity: 4)
        a.shot("after-delete")
        if undo.exists { undo.tap(); a.pause(0.8) }
        a.check("Undo brings it back after Delete", a.counter == before, severity: 4, detail: "\(before ?? "-") then \(a.counter ?? "-")")

        // Undo waits 5 seconds, then goes.
        a.flickUp()
        a.pause(6)
        a.shot("undo-gone")
        a.check("Undo leaves after about 5 seconds", !a.app.buttons["Undo"].exists, severity: 1)

        // Through the whole day to the end.
        var guardN = 0
        while a.app.buttons["Keep something new"].exists, a.counter != nil, guardN < 20 {
            a.flickUp(); a.pause(0.9); guardN += 1
        }
        a.pause(1)
        a.shot("end-of-day")
        a.accessibility("end-of-day")
        a.labels("end-of-day")
        a.check("the end of the day says so, with one choice", a.app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Shoebox'")).count > 0, severity: 2)
    }

    // J3. An opened post: the words, Edit, Delete and Undo, the moves as words.
    func test03_OpenedEditDelete() {
        let a = Audit("J3-opened-edit-delete")
        defer { a.finish() }
        a.launch(["-screen", "opened"])
        a.pause(1)
        a.shot("opened")
        a.labels("opened")
        a.expect("the moves are words: Next", a.app.buttons["Next"])
        a.expect("the moves are words: Put away", a.app.buttons["Put away"])
        a.app.swipeUp()
        a.pause(0.6)
        a.shot("opened-scrolled")
        a.tap("Edit", a.app.buttons["Edit"])
        a.pause(1)
        a.shot("edit")
        a.accessibility("edit")
        a.labels("edit")
        let title = a.field("edit.title", "Title")
        if a.expect("Edit shows the title", title) {
            title.tap()
            a.app.typeText(" (audit)")
            a.shot("edit-typing", note: "the panel rides the keyboard")
        }
        a.tap("Keep", a.app.buttons["Keep"])
        a.pause(1)
        a.shot("after-keep")
        a.check("the edit shows on the post", a.any(containing: "(audit)").exists, severity: 3)

        // Delete: the last word of Edit, soft, with Undo.
        a.tap("Edit again", a.app.buttons["Edit"])
        a.pause(1)
        a.app.swipeUp()
        a.shot("edit-bottom")
        a.tap("Delete", a.app.buttons["Delete"])
        a.pause(1)
        a.shot("after-delete")
        a.check("Delete closes the post and offers Undo", a.app.buttons["Undo"].waitForExistence(timeout: 2) && !a.app.buttons["Edit"].exists, severity: 3)
        a.check("Undo says what it undoes (Deleted)", a.any(containing: "Deleted").exists, severity: 2)
        a.labels("after-delete")
    }

    // J4. Keep something new, in the app: a note with a reason that names a day.
    func test04_KeepSomethingNew() {
        let a = Audit("J4-keep-new")
        defer { a.finish() }
        a.launch()
        let boxBefore = a.boxCount
        a.tap("+ New", a.app.buttons["Keep something new"], severity: 4)
        a.pause(1.2)
        a.shot("new-empty")
        a.accessibility("new-empty")
        a.labels("new-empty")
        a.check("Keep waits until there is something to keep", !(a.app.buttons["Keep"].isEnabled), severity: 2)
        let words = a.field("write.words", "What to keep", "Paste a link or write a note")
        if a.expect("the words field is there and ready", words) {
            words.tap()
            a.app.typeText("Call the dentist about Sam's cleaning")
        }
        let why = a.field("write.why", "Why", "Optional. Before the trip")
        if a.expect("the Why field is there", why) {
            why.tap()
            a.app.typeText("Before Friday")
        }
        a.pause(0.6)
        a.shot("new-filled", note: "the return line should read the day from the Why")
        a.labels("new-filled")
        a.check("the return line reads Friday from the Why", a.any(containing: "Back Thursday").exists || a.button(startingWith: "Back").label.contains("Thursday"), severity: 3)
        a.tap("Photo or file", a.button(startingWith: "Photo"), severity: 2)
        a.pause(0.8)
        a.shot("photo-or-file-menu")
        a.check("the menu offers Photo Library, Take Photo, Choose File",
                a.app.buttons["Photo Library"].exists && a.app.buttons["Choose File"].exists, severity: 2)
        // Close the menu without choosing.
        a.app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        a.pause(0.6)
        a.tap("Keep", a.app.buttons["Keep"], severity: 4)
        a.pause(1.5)
        a.shot("after-keep")
        a.labels("after-keep")
        a.check("the new post went into the box", (a.boxCount ?? 0) > (boxBefore ?? 0), severity: 3,
                detail: "\(boxBefore ?? -1) then \(a.boxCount ?? -1)")
    }

    // J5. The Shoebox: open it, the topics, search, Put away and Just put away, bring one back.
    func test05_TheShoebox() {
        let a = Audit("J5-shoebox")
        defer { a.finish() }
        a.launch()
        // Put one away first, so Just put away has something.
        let firstTitle = a.app.staticTexts.allElementsBoundByIndex.first { $0.exists && $0.label.count > 8 && !$0.label.contains(" of ") }?.label ?? ""
        a.pullDown()
        a.pause(6.5)
        a.tap("the box", a.button(startingWith: "Your Shoebox"), severity: 4)
        a.pause(1.2)
        a.shot("shoebox")
        a.accessibility("shoebox")
        a.labels("shoebox")
        a.expect("the Shoebox has Today to go back", a.app.buttons["Today"])
        a.expect("the Shoebox has Settings", a.app.buttons["Settings"])
        a.app.swipeUp()
        a.pause(0.6)
        a.shot("shoebox-scrolled")
        a.app.swipeDown()
        a.pause(0.4)

        let putAway = a.button(startingWith: "Put away (")
        if a.tap("Put away (n)", putAway) {
            a.pause(1)
            a.shot("put-away")
            a.accessibility("put-away")
            a.labels("put-away")
            a.expect("Just put away is at the top", a.text(containing: "Just put away"))
            if !firstTitle.isEmpty { a.check("what was just put away is listed", a.text(containing: String(firstTitle.prefix(18))).exists, severity: 3, detail: firstTitle) }
            a.expect("it says when (Put away today)", a.text(containing: "Put away today"), severity: 2)
            // Open a topic.
            let topic = a.app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^[A-Z][A-Za-z &]+, [0-9]+$")).firstMatch
            if topic.exists { topic.tap(); a.pause(0.8); a.shot("topic-open") }
            // Back to the Shoebox.
            let back = a.button(startingWith: "Shoebox")
            if back.exists { back.tap() } else { a.button(startingWith: "Put away").tap() }
            a.pause(0.8)
        }

        let search = a.field("Search everything")
        if a.expect("search is there", search) {
            search.tap()
            a.app.typeText("band")
            a.pause(1)
            a.shot("search-band")
            a.labels("search-band")
            a.check("search finds the band posts", a.text(containing: "band").exists || a.text(containing: "Band").exists, severity: 3)
            a.app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
            a.app.typeText("zzqx")
            a.pause(0.8)
            a.shot("search-nothing")
            a.check("search with no match says so", a.text(containing: "Nothing found").exists || a.text(containing: "No ").exists, severity: 2)
        }
        // Bring back from an opened row: open the first row and look for Bring back or the moves.
        a.app.terminate()
    }

    // J6. Settings: every row opens its own screen with its choices as words, and comes back.
    func test06_Settings() {
        let a = Audit("J6-settings")
        defer { a.finish() }
        a.launch(["-screen", "settings"])
        a.pause(1)
        a.shot("settings")
        a.accessibility("settings")
        a.labels("settings")
        for row in ["Each day", "Look", "Pictures", "Backups", "How Shoebox works", "Privacy"] {
            let e = a.button(startingWith: row)
            if !e.exists { a.app.swipeUp(); a.pause(0.4) }
            guard a.tap(row, a.button(startingWith: row), severity: 2) else { continue }
            a.pause(1)
            let name = row.lowercased().replacingOccurrences(of: " ", with: "-")
            a.shot(name)
            a.accessibility(name)
            a.labels(name)
            if row == "How Shoebox works" { a.pause(2.5); a.shot(name + "-later", note: "the looping pictures move") }
            if row == "Look" {
                if a.tap("Stone", a.button(startingWith: "Stone"), severity: 2) { a.pause(0.8); a.shot("look-stone") }
                a.button(startingWith: "Pistachio").tap()
            }
            a.tap("‹ Settings", a.button(startingWith: "‹ Settings"), severity: 3)
            a.pause(0.6)
        }
        a.app.swipeUp(); a.pause(0.5)
        a.shot("settings-bottom")
        if a.tap("Delete everything", a.button(startingWith: "Delete everything"), severity: 2) {
            a.pause(1)
            a.shot("delete-everything")
            a.labels("delete-everything")
            a.check("Delete everything explains and offers a way out",
                    a.button(startingWith: "‹ Settings").exists || a.app.buttons["Cancel"].exists, severity: 3)
            if a.button(startingWith: "‹ Settings").exists { a.button(startingWith: "‹ Settings").tap() }
        }
        a.tap("Close", a.app.buttons["Close"])
        a.pause(1)
        a.check("Close goes back", !a.app.buttons["Close"].exists, severity: 3)
    }

    // J7. Empty and edge states: nothing on Today, nothing kept at all.
    func test07_EmptyStates() {
        let a = Audit("J7-empty-states")
        defer { a.finish() }
        a.launch(["-screen", "clear"])
        a.pause(1)
        a.shot("today-clear")
        a.accessibility("today-clear")
        a.labels("today-clear")
        let go = a.app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Go through'")).firstMatch
        if a.tap("Go through your Shoebox", go, severity: 2) {
            a.pause(1.2)
            a.shot("going-through")
            a.labels("going-through")
            a.check("going through shows a post", a.app.buttons["Keep something new"].exists, severity: 3)
        }
    }
}
