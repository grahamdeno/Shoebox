import XCTest

/// The edges of the UX audit (docs/audit/08-ux-audit.md, sections 2 and 10): a year of keeping and the posts that
/// break layouts (J9), no pictures at all (J9b), and Shoebox Plus in the store and in TestFlight (J10).
@MainActor
final class Edges: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    // J9. 500 more posts: long titles, one very long word, other languages and scripts, emoji, a bare link, no title.
    func test09_HeavyData() {
        let a = Audit("J9-heavy-data")
        defer { a.finish() }
        a.launch(["-dataset", "heavy"], settle: 0)
        a.respond("launch to Today, 500 posts", timeout: 15) { a.app.buttons["Keep something new"].exists }
        a.pause(1)
        a.shot("today")
        a.accessibility("today-heavy")
        a.labels("today")
        a.check("Today still shows where you are", a.counter != nil, severity: 2, detail: a.counter ?? "no counter")

        a.flickUp()
        a.respond("flick up to Undo, 500 posts") { a.app.buttons["Undo"].exists }
        a.pause(0.6)

        a.tap("the box", a.button(startingWith: "Your Shoebox"), severity: 4)
        a.respond("box to the Shoebox, 500 posts", timeout: 8) { a.app.buttons["Settings"].exists }
        a.pause(0.8)
        a.shot("shoebox", note: "Undo from the flick sits low, above search, not over Settings (UX-12)")
        a.check("Undo leaves the Shoebox's Settings free", a.app.buttons["Settings"].isHittable, severity: 2)
        a.accessibility("shoebox-heavy")
        a.labels("shoebox")
        for _ in 0..<8 { a.app.swipeUp(velocity: .fast) }
        a.pause(0.8)
        a.shot("shoebox-deep", note: "after eight fast scrolls")
        a.check("still running after fast scrolling", a.app.state == .runningForeground, severity: 4)
        for _ in 0..<8 { a.app.swipeDown(velocity: .fast) }
        a.pause(0.6)

        let search = a.field("Search everything")
        if a.expect("search is there", search) {
            search.tap()
            a.app.typeText("Donau")
            a.respond("search across 500 posts") { a.text(containing: "Donau").exists }
            a.pause(0.6)
            a.shot("search-long-word", note: "one 57-letter word: it should wrap or shorten, never run off the screen")
            a.accessibility("search-long-word")
            a.check("the long word is found", a.text(containing: "Donau").exists, severity: 3)
            a.app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5))
            a.app.typeText("週末")
            a.pause(1)
            a.shot("search-japanese")
            a.check("Japanese words are found", a.text(containing: "週末").exists, severity: 2)
            a.app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
            a.app.typeText("قائمة")
            a.pause(1)
            a.shot("search-arabic", note: "right-to-left words in a left-to-right list")
            a.check("Arabic words are found", a.text(containing: "قائمة").exists, severity: 2)
            // Open the long title.
            a.app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5))
            a.app.typeText("sensible person")
            a.pause(1)
            let row = a.app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "sensible person")).firstMatch
            if a.tap("the long-title post", row, severity: 2) {
                a.pause(1.2)
                a.shot("opened-long-title")
                a.accessibility("opened-long-title")
                a.labels("opened-long-title")
                a.check("the opened post has its moves", a.app.buttons["Put away"].exists, severity: 3)
            }
        }
        a.check("still running at the end", a.app.state == .runningForeground, severity: 4)
    }

    // J9b. No pictures anywhere: every post is Plum lit warm with Sunflower (CLAUDE.md, design rules).
    func test09b_NoPhotos() {
        let a = Audit("J9b-no-photos")
        defer { a.finish() }
        a.launch(["-dataset", "nophotos"])
        a.shot("today")
        a.accessibility("today-no-photos")
        a.labels("today")
        a.tapPost()
        a.pause(1)
        a.shot("opened")
        a.accessibility("opened-no-photos")
        a.tap("Close", a.app.buttons["Close"])
        a.pause(0.8)
        a.flickUp()
        a.pause(0.9)
        a.shot("next")
        a.tap("the box", a.button(startingWith: "Your Shoebox"), severity: 3)
        a.pause(1.2)
        a.shot("shoebox", note: "rows with no picture have no empty tile")
    }

    // J10. Shoebox Plus. In the store after the first week, the offer and what happens when the App Store can't be
    // reached (an unsigned simulator build has no product). In TestFlight, free: a first name and Get address.
    // Get address is never tapped: it would ask the live relay for a real address.
    func test10_Plus() {
        let a = Audit("J10-plus")
        defer { a.finish() }

        a.launch(["-screen", "settings", "-plusState", "store"])
        a.pause(1)
        a.shot("settings-store")
        a.labels("settings-store")
        a.expect("Settings offers Email after the first week", a.text(containing: "Email"), severity: 3)
        if a.tap("Your Shoebox address", a.button(startingWith: "Your Shoebox address"), severity: 3) {
            a.pause(1)
            a.shot("email-store")
            a.accessibility("email-store")
            a.labels("email-store")
            let buy = a.button(startingWith: "Get your address with Shoebox Plus")
            if a.tap("Get your address with Shoebox Plus", buy, severity: 3) {
                a.respond("the App Store answers, or the app says it couldn't", timeout: 10) {
                    a.text(containing: "App Store").exists || a.text(containing: "Waiting").exists
                }
                a.pause(1)
                a.shot("after-buy")
                a.labels("after-buy")
                a.check("with no App Store the app says so plainly and stays put",
                        a.text(containing: "Couldn't reach the App Store").exists && a.app.state == .runningForeground, severity: 2)
            }
            // Restore purchases is on Settings itself, at the end of Help and about.
            a.tap("‹ Settings", a.button(startingWith: "‹ Settings"), severity: 2)
            a.pause(0.6)
            a.app.swipeUp()
            a.pause(0.5)
            a.expect("Restore purchases is offered", a.button(startingWith: "Restore purchases"), timeout: 2, severity: 1)
        }

        a.launch(["-screen", "settings", "-plusState", "beta"])
        a.pause(1)
        if a.tap("Your Shoebox address", a.button(startingWith: "Your Shoebox address"), severity: 3) {
            a.pause(1.2)
            a.shot("email-testflight")
            a.accessibility("email-testflight")
            a.labels("email-testflight")
            a.check("TestFlight says it is free", a.text(containing: "Free while you test").exists, severity: 2)
            a.expect("a first name field", a.field("Your first name"), severity: 3)
            a.expect("Get address is a word", a.app.buttons["Get address"], severity: 3)
            a.expect("buying stays possible for App Review", a.button(startingWith: "Buy Shoebox Plus"), severity: 2)
        }
    }
}
