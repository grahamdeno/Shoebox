import XCTest

/// J8. Time is the product: replay five weeks of one life in a few minutes.
/// Day 0 the school newsletter arrives (six dates, from the sample data). The app is relaunched with its clock moved on
/// (`-dayOffset N`, debug only) and the store kept on disk (`-replay YES`), so each day sees what the days before left.
/// What should happen (SPEC section 4, Email row, and 2.4):
///   day 0   the dates arrive on Today, shown once
///   day 4   the first date (about 9 days out) is back: 5 days before
///   day 9   picture day is today; put it away
///   day 11  it is under Just put away
///   day 13  it has left Just put away (3 days), still in Put away
///   day 20  the concert of week one moved to Kept on its own
///   day 35  the last date is past; all six are in Kept
@MainActor
final class TimeReplay: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func test08_FiveWeeks() {
        let a = Audit("J8-time-replay")
        defer { a.finish() }
        for day in [0, 4, 9, 11, 13, 20, 35] {
            var args = ["-replay", "YES", "-dayOffset", "\(day)"]
            if day == 0 { args += ["-replayReset", "YES"] }
            a.launch(args)
            a.pause(1)
            a.shot("day\(day)-today")
            a.labels("day\(day)-today")
            let onToday = a.counter
            a.check("day \(day): Today has something or says it is clear", onToday != nil || a.text(containing: "Shoebox").exists, severity: 2,
                    detail: onToday ?? "no counter")

            if day == 9 {
                // Picture day should be up now. Find it by going through Today, then pull it down.
                var found = false
                for _ in 0..<12 {
                    if a.text(containing: "Picture day").exists { found = true; break }
                    guard a.counter != nil else { break }
                    a.flickUp(); a.pause(1)
                }
                a.check("day 9: Picture day is on Today", found, severity: 4)
                if found {
                    a.shot("day9-picture-day")
                    a.pullDown(); a.pause(6)
                }
                a.launch(args)
            }

            a.tap("the box", a.button(startingWith: "Your Shoebox"), severity: 3)
            a.pause(1.2)
            a.shot("day\(day)-shoebox")
            a.labels("day\(day)-shoebox")
            let putAway = a.button(startingWith: "Put away (")
            if putAway.exists {
                putAway.tap(); a.pause(1)
                a.shot("day\(day)-put-away")
                a.labels("day\(day)-put-away")
                let just = a.text(containing: "Just put away").exists
                let picture = a.text(containing: "Picture day").exists
                switch day {
                case 11: a.check("day 11: Picture day is under Just put away", just && picture, severity: 3)
                case 13: a.check("day 13: Just put away has let it go after 3 days", !just, severity: 2)
                case 20: a.check("day 20: the week-one concert moved to Kept on its own", find(a, "Fall band concert"), severity: 3)
                case 35: a.check("day 35: the winter concert is past and in Kept", find(a, "Winter band concert"), severity: 3)
                default: break
                }
            } else if day >= 11 {
                a.check("day \(day): Put away (n) is offered", false, severity: 3)
            }
        }
    }

    /// On screen, or found by searching Put away (topics are closed until tapped).
    private func find(_ a: Audit, _ title: String) -> Bool {
        if a.text(containing: title).exists { return true }
        let search = a.field("Search everything")
        guard search.waitForExistence(timeout: 2) else { return false }
        search.tap()
        a.app.typeText(title)
        a.pause(1)
        a.shot("search-\(title.replacingOccurrences(of: " ", with: "-"))")
        return a.text(containing: title).exists
    }
}
