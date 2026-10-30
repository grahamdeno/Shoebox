import Foundation
import Testing
@testable import ShoeboxCore

// Cases ported from the old app's tests/ai.test.js ("children's names are swapped out before AI",
// "school posts carry the child's name, which never goes to the AI").
struct NameMaskRulesTests {
    @Test func namesSplitOnCommasAndAnd() {
        #expect(NameMask.names(from: "Ava, Max and Alex") == ["Ava", "Max", "Alex"])
        #expect(NameMask.names(from: "Andy") == ["Andy"])
        #expect(NameMask.names(from: "Brandon and Sandra") == ["Brandon", "Sandra"])
        #expect(NameMask.names(from: "  ").isEmpty)
    }

    @Test func namesAreMaskedAsWholeWordsInAnyCase() {
        #expect(NameMask.mask("Alex is in 8th grade; ALEX plays band. Alexandersen is someone else.", child: "Alex")
                == "{child} is in 8th grade; {child} plays band. Alexandersen is someone else.")
        #expect(NameMask.mask("Ava and Max", child: "Ava, Max") == "{child} and {child}")
        #expect(NameMask.mask("Alex has band Thursday", child: "Alex") == "{child} has band Thursday")
    }

    @Test func oneLetterNamesAndNoNameLeaveTextAlone() {
        #expect(NameMask.mask("J has band", child: "J") == "J has band")
        #expect(NameMask.mask("Band is Thursday", child: "") == "Band is Thursday")
    }

    @Test func theTokenIsPutBack() {
        #expect(NameMask.unmask("{child}'s concert is Thursday", child: "Alex") == "Alex's concert is Thursday")
        #expect(NameMask.unmask("{child}'s concert is Thursday", child: "") == "Your child's concert is Thursday")
        #expect(NameMask.unmask("{CHILD}, those lights are yours Thursday", child: "Alex, Max") == "Alex, those lights are yours Thursday")
    }

    @Test func yourChildIsCapitalizedAtAnySentenceStart() {
        #expect(NameMask.unmask("Bring a coat. {child} needs it on the trip.", child: "") == "Bring a coat. Your child needs it on the trip.")
        #expect(NameMask.unmask("Pack lunch for {child}.", child: "") == "Pack lunch for your child.")
    }

    @Test func mentions() {
        #expect(NameMask.mentions("ALEX plays Thursday", child: "Alex"))
        #expect(!NameMask.mentions("Alexandersen plays Thursday", child: "Alex"))
        #expect(NameMask.mentions("{child} has band", child: ""))
        #expect(!NameMask.mentions("Band is Thursday", child: ""))
        #expect(NameMask.mentions("Max has practice", child: "Ava and Max"))
    }

    @Test func maskThenUnmaskRoundTrips() {
        let masked = NameMask.mask("Alex has band Thursday", child: "Alex")
        #expect(!masked.contains("Alex"))
        #expect(NameMask.unmask(masked, child: "Alex") == "Alex has band Thursday")
    }
}
