import Foundation
import Testing
@testable import ShoeboxCore

// Cases ported from the old app's tests/model.test.js and tests/ai.test.js.
struct DetectionRulesTests {
    func one(_ text: String) throws -> Detection.Draft {
        let all = Detection.drafts(fromText: text)
        #expect(all.count == 1)
        return try #require(all.first)
    }

    @Test func findURLTrimsTrailingPunctuation() {
        #expect(Detection.findURL("see https://example.com/a-b).") == "https://example.com/a-b")
        #expect(Detection.findURL("no link here") == "")
    }

    @Test func bareLinkIsALinkAndProseWithALinkIsANote() throws {
        let link = try one("https://example.com/platform-team-design")
        #expect(link.kind == .link)
        #expect(link.title == "Platform team design")
        let note = try one("Ask about PI objectives before Thursday, and reread https://example.com/x when there is time to think it through")
        #expect(note.kind == .note)
        #expect(note.url == "https://example.com/x")
        #expect(Detection.drafts(fromText: "   ").isEmpty)
    }

    @Test func fileKinds() {
        #expect(Detection.kind(mime: "image/heic", fileName: "IMG_1.HEIC") == .photo)
        #expect(Detection.kind(mime: "", fileName: "report.PDF") == .pdf)
        #expect(Detection.kind(mime: "text/markdown", fileName: "notes.md") == .file) // old TEXT is file in 2.0
        #expect(Detection.kind(mime: "application/vnd.openxmlformats-officedocument.wordprocessingml.document", fileName: "a.docx") == .file)
        #expect(Detection.kind(mime: "video/quicktime", fileName: "clip.mov") == .video)
        #expect(Detection.kind(mime: "audio/mpeg", fileName: "memo.mp3") == .file)
        #expect(Detection.kind(mime: nil, fileName: nil) == .file)
    }

    @Test func titleFromURLFallsBackToHost() {
        #expect(Detection.titleFromURL("https://www.example.com/") == "example.com")
        #expect(Detection.titleFromURL("not a url") == "not a url")
        #expect(Detection.titleFromURL("https://example.com/2024") == "example.com")
    }

    @Test func youTubeLinksBecomeVideosWithAThumbnail() throws {
        for u in ["https://www.youtube.com/watch?v=UF8uR6Z6KLc", "https://youtu.be/UF8uR6Z6KLc?t=30",
                  "https://youtube.com/shorts/UF8uR6Z6KLc", "https://m.youtube.com/watch?feature=share&v=UF8uR6Z6KLc"] {
            #expect(Detection.youTubeId(u) == "UF8uR6Z6KLc", "\(u)")
        }
        #expect(Detection.youTubeId("https://example.com/watch") == nil)
        let d = try one("https://youtu.be/UF8uR6Z6KLc")
        #expect(d.kind == .video)
        #expect(d.videoId == "UF8uR6Z6KLc")
        #expect(d.imageURL == "https://i.ytimg.com/vi/UF8uR6Z6KLc/hqdefault.jpg")
        #expect(d.title == "YouTube video")
    }

    @Test func imageAndVideoFileLinks() throws {
        let photo = try one("https://example.com/whiteboard.jpg")
        #expect(photo.kind == .photo)
        #expect(photo.imageURL == "https://example.com/whiteboard.jpg")
        #expect(try one("https://example.com/clip.mp4?x=1").kind == .video)
    }

    @Test func aListOfLinksBecomesOneDraftPerLink() {
        let out = Detection.drafts(fromText: "https://a.com/one\nhttps://youtu.be/UF8uR6Z6KLc\n- https://b.com/two")
        #expect(out.map(\.kind) == [.link, .video, .link])
        #expect(out.map(\.url) == ["https://a.com/one", "https://youtu.be/UF8uR6Z6KLc", "https://b.com/two"])
    }

    @Test func quotesAreRecognisedWithTheirAuthor() throws {
        let a = try #require(Detection.parseQuote("\u{201C}Plans are worthless, but planning is everything.\u{201D} \u{2014} Dwight D. Eisenhower"))
        #expect(a.text == "Plans are worthless, but planning is everything.")
        #expect(a.author == "Dwight D. Eisenhower")
        let b = try #require(Detection.parseQuote("How we spend our days is how we spend our lives.\n\u{2014} Annie Dillard"))
        #expect(b.text == "How we spend our days is how we spend our lives.")
        #expect(b.author == "Annie Dillard")
        let c = try #require(Detection.parseQuote("\"Simplicity is prerequisite for reliability.\""))
        #expect(c.text == "Simplicity is prerequisite for reliability.")
        #expect(c.author == "")
        let d = try one("Waste no more time arguing what a good man should be. Be one. - Marcus Aurelius")
        #expect(d.kind == .quote)
        #expect(d.author == "Marcus Aurelius")
    }

    @Test func toDosAndPlainNotesAreNotQuotes() throws {
        #expect(Detection.parseQuote("Call the plumber about the leak - Tuesday") == nil)
        #expect(Detection.parseQuote("Finish the PI objectives draft. - Friday") == nil)
        #expect(try one("Ask about the sprint review format before Thursday").kind == .note)
        let note = try one("Call the plumber about the leak - Tuesday")
        #expect(note.kind == .note)
        #expect(note.title == "Call the plumber about the leak - Tuesday")
    }

    @Test func aSharedLinkWithItsPageTitleOnTheNextLineIsATitledLink() throws {
        let d = try one("https://coolhunting.com/buy/star-child-special-edition-by-claire-a-nivola/\nStar Child: Special Edition by Claire A Nivola - COOL HUNTING\u{00AE}")
        #expect(d.kind == .link)
        #expect(d.title == "Star Child: Special Edition by Claire A Nivola - COOL HUNTING\u{00AE}")
        #expect(try one("Two paragraphs of my own thinking about this.\n\nhttps://a.com/x\nand more").kind == .note)
    }

    @Test func noteTitleIsTheFirstLineCutAt90() throws {
        let long = String(repeating: "word ", count: 30) + "\nsecond line"
        let d = try one(long)
        #expect(d.kind == .note)
        #expect(d.title.count <= 88)
        #expect(d.title.hasSuffix("\u{2026}"))
    }

    @Test func draftFromURLUsesTitleOrFallsBack() throws {
        let url = try #require(URL(string: "https://example.com/platform-team-design"))
        #expect(Detection.draft(fromURL: url, title: nil).title == "Platform team design")
        let titled = Detection.draft(fromURL: url, title: "The page")
        #expect(titled.title == "The page")
        #expect(titled.kind == .link)
    }

    @Test func wrappedLinksUnwrapToTheRealAddress() {
        let safe = "https://nam12.safelinks.protection.outlook.com/?url=https%3A%2F%2Fmyrtlegrovemiddle.givebacks.com%2Fshop%2Fitems%2F0b1c061aa483cd&data=05%7C02&reserved=0"
        #expect(Detection.unwrapLink(safe) == "https://myrtlegrovemiddle.givebacks.com/shop/items/0b1c061aa483cd")
        #expect(Detection.unwrapLink("https://example.com/a") == "https://example.com/a")
        #expect(Detection.unwrapLink("not a link") == "not a link")
        #expect(Detection.unwrapLink("https://www.google.com/url?q=https%3A%2F%2Fexample.com%2Fa&sa=D") == "https://example.com/a")
        #expect(Detection.unwrapLink("https://urldefense.com/v3/__https://example.com/a__;!!abc") == "https://example.com/a")
    }

    @Test func pastedSafeLinkSavesTheRealAddress() throws {
        let d = try one("https://nam12.safelinks.protection.outlook.com/?url=https%3A%2F%2Fexample.com%2Fspring-concert&data=05")
        #expect(d.url == "https://example.com/spring-concert")
        #expect(d.title == "Spring concert")
    }
}
