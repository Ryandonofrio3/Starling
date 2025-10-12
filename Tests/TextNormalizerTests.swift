import XCTest
@testable import Starling

final class TextNormalizerTests: XCTestCase {
    private let normalizer = TextNormalizer()

    func testNewLineConversion() {
        let options = PreferencesStore.TextCleanupOptions(
            normalizeNumbers: false,
            spokenPunctuation: false,
            normalizeNewlines: true,
            autoCapitalizeFirstWord: false
        )

        let result = normalizer.normalize("first new line second", options: options)
        XCTAssertEqual(result, "first\nsecond")
    }

    func testNewParagraphConversion() {
        let options = PreferencesStore.TextCleanupOptions(
            normalizeNumbers: false,
            spokenPunctuation: false,
            normalizeNewlines: true,
            autoCapitalizeFirstWord: false
        )

        let result = normalizer.normalize("alpha new paragraph bravo", options: options)
        XCTAssertEqual(result, "alpha\n\nbravo")
    }

    func testTrailingNewLinePreservedAfterCleanup() {
        let options = PreferencesStore.TextCleanupOptions(
            normalizeNumbers: false,
            spokenPunctuation: false,
            normalizeNewlines: true,
            autoCapitalizeFirstWord: false
        )

        let result = normalizer.normalize("hello new line", options: options)
        XCTAssertEqual(result, "hello\n")
    }
}

extension TextNormalizerTests {
    func testHyphenatedNewLineConversion() {
        let options = PreferencesStore.TextCleanupOptions(
            normalizeNumbers: false,
            spokenPunctuation: false,
            normalizeNewlines: true,
            autoCapitalizeFirstWord: false
        )

        let result = normalizer.normalize("first new-line second", options: options)
        XCTAssertEqual(result, "first\nsecond")
    }

    func testConcatenatedNewLineConversion() {
        let options = PreferencesStore.TextCleanupOptions(
            normalizeNumbers: false,
            spokenPunctuation: false,
            normalizeNewlines: true,
            autoCapitalizeFirstWord: false
        )

        let result = normalizer.normalize("first newline second", options: options)
        XCTAssertEqual(result, "first\nsecond")
    }

    func testHyphenatedNewParagraphConversion() {
        let options = PreferencesStore.TextCleanupOptions(
            normalizeNumbers: false,
            spokenPunctuation: false,
            normalizeNewlines: true,
            autoCapitalizeFirstWord: false
        )

        let result = normalizer.normalize("alpha new-paragraph bravo", options: options)
        XCTAssertEqual(result, "alpha\n\nbravo")
    }

    func testConcatenatedNewParagraphConversion() {
        let options = PreferencesStore.TextCleanupOptions(
            normalizeNumbers: false,
            spokenPunctuation: false,
            normalizeNewlines: true,
            autoCapitalizeFirstWord: false
        )

        let result = normalizer.normalize("alpha newparagraph bravo", options: options)
        XCTAssertEqual(result, "alpha\n\nbravo")
    }

    func testNewLineWithTrailingPunctuationRemoved() {
        let options = PreferencesStore.TextCleanupOptions(
            normalizeNumbers: false,
            spokenPunctuation: false,
            normalizeNewlines: true,
            autoCapitalizeFirstWord: false
        )

        let result = normalizer.normalize("hello new line, world", options: options)
        XCTAssertEqual(result, "hello\nworld")
    }

    func testMultipleConsecutiveNewLinesTokens() {
        let options = PreferencesStore.TextCleanupOptions(
            normalizeNumbers: false,
            spokenPunctuation: false,
            normalizeNewlines: true,
            autoCapitalizeFirstWord: false
        )

        let result = normalizer.normalize("a new line new line b", options: options)
        XCTAssertEqual(result, "a\n\nb")
    }

    func testNewParagraphAtSentenceEndWithTrailingPeriod() {
        let options = PreferencesStore.TextCleanupOptions(
            normalizeNumbers: false,
            spokenPunctuation: false,
            normalizeNewlines: true,
            autoCapitalizeFirstWord: false
        )

        let result = normalizer.normalize("alpha new paragraph.", options: options)
        XCTAssertEqual(result, "alpha\n\n")
    }
}
