import XCTest

/// J11. The jobs people come for, each from Today, counted in taps and timed in app responses
/// (docs/audit/benchmarks.json holds the targets; docs/audit/08-ux-audit.md section 10).
@MainActor
final class Benchmarks: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    func test11_Jobs() {
        let a = Audit("J11-benchmarks")
        defer { a.finish() }

        // Open a post and close it.
        a.launch()
        a.begin("open a post and close it")
        a.tapPost()
        a.respond("tap to opened") { a.app.buttons["Close"].exists }
        a.tap("Close", a.app.buttons["Close"])
        a.respond("Close to Today") { a.app.buttons["Keep something new"].exists }
        a.done("open a post and close it", a.app.buttons["Keep something new"].exists)

        // Next, then Undo.
        let before = a.counter
        a.begin("next, then undo")
        a.flickUp()
        a.respond("flick up to Undo") { a.app.buttons["Undo"].exists }
        a.tap("Undo", a.app.buttons["Undo"])
        a.respond("Undo to the post back") { a.counter == before }
        a.done("next, then undo", a.counter == before)

        // Put away, then Undo.
        a.begin("put away, then undo")
        a.pullDown()
        a.respond("pull down to Undo") { a.app.buttons["Undo"].exists }
        a.tap("Undo", a.app.buttons["Undo"])
        a.respond("Undo to the post back after Put away") { a.counter == before }
        a.done("put away, then undo", a.counter == before)

        // Keep a note with a reason that names a day.
        a.launch()
        let boxBefore = a.boxCount ?? 0
        a.begin("keep a note with a reason")
        a.tap("+ New", a.app.buttons["Keep something new"], severity: 4)
        a.respond("+ New to the writing screen") { a.field("write.words", "What to keep", "Paste a link or write a note").exists }
        a.tap("the words", a.field("write.words", "What to keep", "Paste a link or write a note"))
        a.app.typeText("Call the dentist about Sam's cleaning")
        a.tap("Why", a.field("write.why", "Why", "Optional. Before the trip"))
        a.app.typeText("Before Friday")
        a.tap("Keep", a.app.buttons["Keep"], severity: 4)
        a.respond("Keep to Today") { a.app.buttons["Keep something new"].exists }
        a.pause(1)
        a.done("keep a note with a reason", (a.boxCount ?? 0) > boxBefore)

        // Find the post put away a moment ago.
        a.launch()
        let title = a.app.staticTexts.allElementsBoundByIndex.first { $0.exists && $0.label.count > 8 && !$0.label.contains(" of ") }?.label ?? ""
        a.pullDown()
        a.pause(6.5)
        a.begin("find what you put away")
        a.tap("the box", a.button(startingWith: "Your Shoebox"), severity: 4)
        a.respond("box to the Shoebox") { a.app.buttons["Settings"].exists }
        a.tap("Put away (n)", a.button(startingWith: "Put away ("))
        a.respond("Put away (n) to the list") { a.text(containing: "Just put away").exists }
        a.shot("found")
        a.done("find what you put away", !title.isEmpty && a.text(containing: String(title.prefix(18))).exists)

        // Change how many come out a day.
        a.launch()
        a.begin("change how many a day")
        a.tap("the box", a.button(startingWith: "Your Shoebox"), severity: 4)
        a.respond("box to the Shoebox, again") { a.app.buttons["Settings"].exists }
        a.tap("Settings", a.app.buttons["Settings"])
        a.respond("Settings opens") { a.button(startingWith: "Each day").exists }
        a.tap("Each day", a.button(startingWith: "Each day"))
        a.respond("Each day opens") { a.app.buttons["5"].exists }
        a.tap("5", a.app.buttons["5"])
        a.pause(0.6)
        a.shot("each-day-5")
        a.button(startingWith: "‹ Settings").tap()
        a.pause(0.6)
        a.done("change how many a day", a.button(startingWith: "Each day").label.contains("5"))
    }
}
