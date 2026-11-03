import Foundation
import Testing
@testable import ShoeboxCore

/// SPEC 2.4: titles worth reading, topics, and folds. The cases are the Put away list of November 2.
struct TidyTests {
    private func item(_ title: String, snippet: String = "", note: String = "", url: String? = nil,
                      origin: String = "", kind: String = "link", subject: String? = nil, id: String? = nil) -> Tidy.Item {
        Tidy.Item(id: id ?? UUID().uuidString, title: title, snippet: snippet, note: note, url: url,
                  origin: origin, emailSubject: subject, kind: kind)
    }

    // MARK: Titles

    @Test func realTitlesAreKeptAsTheyAre() {
        #expect(Tidy.title(item("Verdant Hexagon Cut Moss Agate Ring", url: "https://envnis.com/ring")) == "Verdant Hexagon Cut Moss Agate Ring")
        #expect(Tidy.title(item("Picture retake day", kind: "email")) == "Picture retake day")
    }

    @Test func placeholders() {
        #expect(Tidy.isPlaceholder("A photo", url: nil))
        #expect(Tidy.isPlaceholder("Id1120837655", url: "https://apps.apple.com/us/app/lovely/id1120837655"))
        #expect(Tidy.isPlaceholder("https://www.instagram.com/reel/DfIT123/", url: nil))
        #expect(Tidy.isPlaceholder("instagram.com", url: "https://www.instagram.com/reel/x"))
        #expect(Tidy.isPlaceholder("", url: nil))
        #expect(!Tidy.isPlaceholder("Band concert", url: nil))
        #expect(!Tidy.isPlaceholder("Idaho trip", url: nil))
    }

    @Test func aBareLinkGetsAPlainName() {
        #expect(Tidy.title(item("https://www.instagram.com/reel/DfIT123/", kind: "email")) == "Instagram reel")
        #expect(Tidy.title(item("Id1120837655", url: "https://apps.apple.com/us/app/lovely/id1120837655")) == "An app on the App Store")
        #expect(Tidy.title(item("https://example.org/a/b")) == "Link from example.org")
        #expect(Tidy.title(item("youtube.com", url: "https://www.youtube.com/watch?v=1")) == "YouTube video")
    }

    @Test func whatThePostSaysComesBeforeTheLinkName() {
        let i = item("Id1120837655", snippet: "Lovely Mail turns your inbox into a calm feed. Free.", url: "https://apps.apple.com/us/app/id1120837655")
        #expect(Tidy.title(i) == "Lovely Mail turns your inbox into a calm feed")
        // A snippet that is only a link is no better.
        #expect(Tidy.title(item("https://x.com/a", snippet: "https://x.com/a")) == "Post on X")
    }

    @Test func aPhotoTakesYourReasonInListsOnly() {
        let photo = item("A photo", note: "Parking pass for Saturday", kind: "photo")
        #expect(Tidy.title(photo, useNote: true) == "Parking pass for Saturday")
        #expect(Tidy.title(photo) == "A photo", "on a post the reason is already shown under the title")
    }

    @Test func longSnippetsAreCutAtAWord() {
        let long = String(repeating: "word ", count: 40)
        let t = Tidy.title(item("A photo", snippet: long, kind: "photo"))
        #expect(t.count <= 100)
        #expect(!t.hasSuffix(" "))
    }

    // MARK: Topics

    @Test func topics() {
        #expect(Tidy.topic(item("No school for students on November 3", origin: "Google Docs")) == .school)
        #expect(Tidy.topic(item("Picture retake day", kind: "email", subject: "Picture retake day")) == .school)
        #expect(Tidy.topic(item("Matthew McConaughey tuna salad recipe", url: "https://instagram.com/reel/1")) == .food)
        #expect(Tidy.topic(item("CNS Watch Bands - Shopping Cart", url: "https://cnswatchbands.com/cart")) == .shopping)
        #expect(Tidy.topic(item("Id1120837655", url: "https://apps.apple.com/us/app/id1120837655")) == .apps)
        #expect(Tidy.topic(item("Building your first data analytics pipeline", kind: "email", subject: "Building your first data analytics pipeline")) == .work)
        #expect(Tidy.topic(item("Devoops on Instagram", url: "https://www.instagram.com/reel/abc")) == .watch)
        #expect(Tidy.topic(item("Have I Been Pwned: check if an email has been in a breach", url: "https://haveibeenpwned.com")) == .reading)
        #expect(Tidy.topic(item("A photo", kind: "photo")) == .other)
    }

    @Test func wordsMatchWholeWordsOnly() {
        // "ring" must not match "during", "cart" not "cartoon".
        #expect(Tidy.topic(item("Notes during the week", kind: "note")) == .other)
        #expect(Tidy.topic(item("A cartoon I liked", kind: "note")) == .other)
    }

    @Test func homeAndMoneySportsAndNewsletters() {
        #expect(Tidy.topic(item("County Tax Paid", kind: "email", subject: "County Tax Paid")) == .home)
        #expect(Tidy.topic(item("You have an upcoming game at Polar Ice House", kind: "email")) == .sports)
        // A newsletter whose subject says nothing is about what it says.
        var newsletter = item("26-27 Duck Weekly Newsletter", kind: "email", subject: "26-27 Duck Weekly Newsletter")
        newsletter.text = "Good morning, Duck families. No school for students on Monday. Picture retake day is Thursday."
        #expect(Tidy.topic(newsletter) == .school)
        // A web page's words are not read: too many of them.
        var page = item("A long article", url: "https://a.com/x")
        page.text = "school school school"
        #expect(Tidy.topic(page) == .reading)
    }

    @Test func anEmailWeCantPlaceIsSomethingElseNotReading() {
        #expect(Tidy.topic(item("Hello from Sam", kind: "email", subject: "Hello from Sam")) == .other)
    }

    // MARK: Topics as a list (Put away)

    @Test func topicsHaveNoFoldsAndShowTheSameTitleOnce() {
        let newer = item("Picture retake day", kind: "email", subject: "Retake day", id: "new")
        let older = item("Picture retake day", kind: "email", subject: "Picture retake day", id: "old")
        let other = item("Report cards go home October 29", kind: "note")
        let groups = Tidy.topics([newer, other, older])
        #expect(groups.count == 1)
        #expect(groups[0].topic == .school)
        #expect(groups[0].rows.map(\.id) == ["new", other.id], "newest kept, order kept, no folds")
        #expect(groups[0].count == 2)
    }

    @Test func topicsAreLargestFirstAndSomethingElseLast() {
        let posts = [
            item("Hello", kind: "note"), item("Hi there", kind: "note"), item("Hey you", kind: "note"),
            item("Tuna salad recipe", url: "https://a.com/1"),
            item("No school Monday", url: "https://b.com/1"), item("Picture day", url: "https://b.com/2"),
        ]
        #expect(Tidy.topics(posts).map(\.topic) == [.school, .food, .other])
    }

    // MARK: Folds and groups

    @Test func postsFromOneEmailFoldTogether() {
        let a = item("No school for students on November 3", url: "https://docs.google.com/document/d/duck/edit?usp=sharing", origin: "Google Docs")
        let b = item("Damaged chargers returned: replacements", url: "https://docs.google.com/document/d/duck/edit", origin: "Google Docs")
        let c = item("Student-led conferences start next week", url: "https://docs.google.com/document/d/duck/edit#h.1", origin: "Google Docs")
        let groups = Tidy.groups([a, b, c])
        #expect(groups.count == 1)
        #expect(groups[0].topic == .school, "most of the fold is about school, so the chargers go with it")
        guard case .fold(_, let title, let items) = groups[0].rows[0] else { Issue.record("expected a fold"); return }
        #expect(items.map(\.id) == [a.id, b.id, c.id], "newest first, as they came")
        #expect(title == "From Google Docs")
    }

    @Test func theSameThingTwiceFoldsUnderItsTitle() {
        let a = item("Picture retake day", kind: "email", subject: "Picture retake day")
        let b = item("Picture retake day", kind: "email", subject: "Picture retake day")
        let rows = Tidy.groups([a, b]).flatMap(\.rows)
        #expect(rows.count == 1)
        guard case .fold(_, let title, let items) = rows[0] else { Issue.record("expected a fold"); return }
        #expect(title == "Picture retake day")
        #expect(items.count == 2)
    }

    @Test func aNewsletterFoldTakesItsSubject() {
        let a = item("Band concert Thursday", kind: "email", subject: "26-27 Duck Weekly Newsletter")
        let b = item("Picture retake day", kind: "email", subject: "26-27 Duck Weekly Newsletter")
        guard case .fold(_, let title, _) = Tidy.groups([a, b])[0].rows[0] else { Issue.record("expected a fold"); return }
        #expect(title == "26-27 Duck Weekly Newsletter")
    }

    @Test func groupsAreLargestFirstAndSomethingElseLast() {
        let posts = [
            item("A photo", kind: "photo"),
            item("A photo", note: "x", kind: "photo", id: "p2"),
            item("Tuna salad recipe", url: "https://a.com/1"),
            item("No school Monday", url: "https://b.com/1"),
            item("Picture day", url: "https://b.com/2"),
        ]
        let topics = Tidy.groups(posts).map(\.topic)
        #expect(topics == [.school, .food, .other])
    }

    @Test func oneOfAKindIsARowNotAFold() {
        let rows = Tidy.groups([item("Tuna salad recipe", url: "https://a.com/1")]).flatMap(\.rows)
        guard case .one = rows[0] else { Issue.record("expected a single row"); return }
    }
}
