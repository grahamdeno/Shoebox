import Foundation
import Testing
@testable import ShoeboxCore

struct MinutesRulesTests {
    @Test func notesCountWordsAtTwoTwentyAMinute() {
        let words = String(repeating: "word ", count: 440)
        #expect(Minutes.estimate(kind: .note, text: words, isBook: false) == 2)
        #expect(Minutes.estimate(kind: .note, text: String(repeating: "word ", count: 600), isBook: false) == 3)
    }

    @Test func shortOrEmptyNotesAreAtLeastOneMinute() {
        #expect(Minutes.estimate(kind: .note, text: "hi", isBook: false) == 1)
        #expect(Minutes.estimate(kind: .note, text: nil, isBook: false) == 1)
    }

    @Test func eachKindHasItsDefault() {
        #expect(Minutes.estimate(kind: .quote, text: nil, isBook: false) == 1)
        #expect(Minutes.estimate(kind: .photo, text: nil, isBook: false) == 1)
        #expect(Minutes.estimate(kind: .link, text: nil, isBook: false) == 6)
        #expect(Minutes.estimate(kind: .pdf, text: nil, isBook: false) == 15)
        #expect(Minutes.estimate(kind: .video, text: nil, isBook: false) == 10)
        #expect(Minutes.estimate(kind: .file, text: nil, isBook: false) == 5)
    }

    @Test func aBookIsOneSitting() {
        #expect(Minutes.estimate(kind: .photo, text: nil, isBook: true) == 30)
        #expect(Minutes.estimate(kind: .link, text: nil, isBook: true) == Minutes.bookSitting)
    }
}

struct SpokenReasonRulesTests {
    @Test func fillerAtTheStartIsRemovedAndTheFirstLetterCapitalized() {
        #expect(SpokenReason.clean("um, read this before the meeting") == "Read this before the meeting")
        #expect(SpokenReason.clean("Uh like, show the kids at dinner") == "Show the kids at dinner")
        #expect(SpokenReason.clean("  umm uh   for the house ") == "For the house")
    }

    @Test func wordsThatOnlyStartLikeFillerStay() {
        #expect(SpokenReason.clean("umbrella deals for the beach") == "Umbrella deals for the beach")
        #expect(SpokenReason.clean("like this one") == "Like this one")
        #expect(SpokenReason.clean("show Kate, um, this weekend") == "Show Kate, um, this weekend")
    }

    @Test func longReasonsAreCutOnAWordBoundary() {
        let long = String(repeating: "abcd ", count: 40) // 200 characters
        let cut = SpokenReason.clean(long)
        #expect(cut.count == 139)
        #expect(cut.hasSuffix("abcd"))
        #expect(SpokenReason.clip("Read this now", max: 9) == "Read this")
        #expect(SpokenReason.clip("Read this, now", max: 11) == "Read this")
    }

    @Test func clipLeavesShortTextAndCutsOneLongWordHard() {
        #expect(SpokenReason.clip("short") == "short")
        let word = String(repeating: "a", count: 150)
        #expect(SpokenReason.clip(word).count == 140)
        #expect(SpokenReason.clip("anything", max: 0) == "")
    }
}

struct VerdictRulesTests {
    @Test func threeVerdicts() {
        #expect(Verdict.allCases == [.done, .later, .drop])
    }

    @Test func doneWordFollowsTheIntent() {
        #expect(VerdictWords.doneWord(kind: .link, intent: .read, reason: "", isBook: false, school: nil) == "Read")
        #expect(VerdictWords.doneWord(kind: .video, intent: .watch, reason: "", isBook: false, school: nil) == "Watched")
        #expect(VerdictWords.doneWord(kind: .link, intent: .listen, reason: "", isBook: false, school: nil) == "Listened")
        #expect(VerdictWords.doneWord(kind: .link, intent: .idea, reason: "", isBook: false, school: nil) == "Tried it")
        #expect(VerdictWords.doneWord(kind: .photo, intent: .reference, reason: "", isBook: false, school: nil) == "Kept")
    }

    @Test func tasksUseTheReasonsVerb() {
        #expect(VerdictWords.doneWord(kind: .link, intent: .task, reason: "Book the campsite for May", isBook: false, school: nil) == "Booked")
        #expect(VerdictWords.doneWord(kind: .note, intent: .task, reason: "call Mom, Sunday", isBook: false, school: nil) == "Called")
        #expect(VerdictWords.doneWord(kind: .note, intent: .task, reason: "Figure out taxes", isBook: false, school: nil) == "Done")
        #expect(VerdictWords.doneWord(kind: .link, intent: nil, reason: "Order before Friday", isBook: false, school: nil) == "Ordered")
    }

    @Test func schoolAndBooksComeFirst() {
        #expect(VerdictWords.doneWord(kind: .note, intent: .task, reason: "Sign the form", isBook: false, school: .action) == "Done")
        #expect(VerdictWords.doneWord(kind: .note, intent: nil, reason: "", isBook: false, school: .decision) == "Decided")
        #expect(VerdictWords.doneWord(kind: .note, intent: nil, reason: "", isBook: true, school: .info) == "Got it")
        #expect(VerdictWords.doneWord(kind: .photo, intent: .read, reason: "", isBook: true, school: nil) == "I've read it")
    }

    @Test func withoutIntentTheKindDecides() {
        #expect(VerdictWords.doneWord(kind: .photo, intent: nil, reason: "", isBook: false, school: nil) == "Kept")
        #expect(VerdictWords.doneWord(kind: .quote, intent: nil, reason: "", isBook: false, school: nil) == "Kept")
        #expect(VerdictWords.doneWord(kind: .pdf, intent: nil, reason: "", isBook: false, school: nil) == "Read")
        #expect(VerdictWords.doneWord(kind: .video, intent: nil, reason: "", isBook: false, school: nil) == "Watched")
        #expect(VerdictWords.doneWord(kind: .note, intent: nil, reason: "", isBook: false, school: nil) == "Done")
    }

    @Test func dropWord() {
        #expect(VerdictWords.dropWord(suggested: false) == "Drop")
        #expect(VerdictWords.dropWord(suggested: true) == "Not for me")
    }
}
