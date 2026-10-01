import XCTest
@testable import NotchNotes

final class TranslationLanguageTests: XCTestCase {
    func testDetectsChineseInput() {
        XCTAssertEqual(TranslationLanguageDetector.detect("今天重庆下暴雨"), .chinese)
        XCTAssertEqual(TranslationLanguageDetector.detect("iPhone 15 发布了"), .chinese)
        XCTAssertEqual(TranslationLanguageDetector.detect("Hello, world"), .english)
        XCTAssertEqual(TranslationLanguageDetector.detect(""), .english)
    }

    func testLanguagePairMapping() {
        XCTAssertEqual(TranslationLanguage.chinese.apiValue, "Chinese")
        XCTAssertEqual(TranslationLanguage.english.apiValue, "English")
        XCTAssertEqual(TranslationLanguage.chinese.opposite, .english)
        XCTAssertEqual(TranslationLanguage.english.opposite, .chinese)
        XCTAssertEqual(TranslationLanguage.chinese.shortName, "中")
        XCTAssertEqual(TranslationLanguage.english.shortName, "EN")
    }

    func testOnlyPlusModelSkipsStreaming() {
        XCTAssertTrue(TranslationModel.flash.supportsStreaming)
        XCTAssertTrue(TranslationModel.lite.supportsStreaming)
        XCTAssertFalse(TranslationModel.plus.supportsStreaming)
    }

    func testHotKeyDisplayString() {
        XCTAssertEqual(HotKeySpec.optionQ.displayString, "⌥Q")
        XCTAssertEqual(HotKeySpec.controlOptionT.displayString, "⌃⌥T")
    }
}
