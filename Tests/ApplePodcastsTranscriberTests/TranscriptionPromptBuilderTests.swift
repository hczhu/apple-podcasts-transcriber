import XCTest
@testable import ApplePodcastsTranscriberCore

final class TranscriptionPromptBuilderTests: XCTestCase {
    func testBuildsPromptFromShowTitleEpisodeTitleAndNotes() {
        let notes = ShowNotes(
            podcastTitle: "Asianometry",
            episodeTitle: "SK hynix and the HBM Revolution",
            itemDescription: "How SK hynix became an AI memory titan"
        )

        XCTAssertEqual(
            TranscriptionPromptBuilder.prompt(from: notes),
            "Asianometry. SK hynix and the HBM Revolution. How SK hynix became an AI memory titan."
        )
    }

    func testStripsHTMLEntitiesAndLinks() {
        let cleaned = TranscriptionPromptBuilder.plainText(
            "<p>Ben&nbsp;Thompson on Big Tech &amp; China.</p>"
                + "<p>Watch at https://example.com/x?y=1 or www.example.com now.</p>"
        )

        XCTAssertEqual(cleaned, "Ben Thompson on Big Tech & China. Watch at or now.")
    }

    func testDecodesNumericEntities() {
        XCTAssertEqual(
            TranscriptionPromptBuilder.plainText("Nvidia&#x2019;s revenue&#160;grew"),
            "Nvidia\u{2019}s revenue grew"
        )
    }

    func testOmitsEpisodeTitleWhenItDuplicatesPodcastTitle() {
        let notes = ShowNotes(
            podcastTitle: "Dithering",
            episodeTitle: "Dithering",
            itemDescription: nil
        )

        XCTAssertEqual(TranscriptionPromptBuilder.prompt(from: notes), "Dithering.")
    }

    func testReturnsNilWhenNotesHoldNothingUsable() {
        let notes = ShowNotes(podcastTitle: nil, episodeTitle: nil, itemDescription: "<p></p>")
        XCTAssertNil(TranscriptionPromptBuilder.prompt(from: notes))
    }

    func testTruncatesAtSentenceBoundaryWithinBudget() {
        let text = "First sentence here. Second sentence runs on much longer than the budget allows."
        let truncated = TranscriptionPromptBuilder.truncated(text, tokenBudget: 8)

        XCTAssertEqual(truncated, "First sentence here.")
    }

    func testTruncatesAtWordBoundaryWhenNoSentenceBreakFits() {
        let text = "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima"
        let truncated = TranscriptionPromptBuilder.truncated(text, tokenBudget: 5)

        XCTAssertFalse(truncated.hasSuffix(" "))
        XCTAssertTrue(text.hasPrefix(truncated))
        XCTAssertEqual(truncated.last?.isLetter, true)
    }

    func testBudgetsCJKCharactersMoreHeavilyThanLatin() {
        let latin = TranscriptionPromptBuilder.truncated(String(repeating: "a ", count: 400), tokenBudget: 100)
        let chinese = TranscriptionPromptBuilder.truncated(String(repeating: "字", count: 400), tokenBudget: 100)

        XCTAssertGreaterThan(latin.count, chinese.count)
        XCTAssertLessThanOrEqual(chinese.count, 67)
    }

    func testEmptyBudgetProducesNoPrompt() {
        let notes = ShowNotes(podcastTitle: "Show", episodeTitle: nil, itemDescription: nil)
        XCTAssertNil(TranscriptionPromptBuilder.prompt(from: notes, tokenBudget: 0))
    }
}
