import XCTest
@testable import NotchNotes

final class TranslationRequestTests: XCTestCase {
    /// 最容易写错的一点：`translation_options` 必须是顶层字段，
    /// 而不是塞进 messages 或 extra_body。
    func testTranslationOptionsAreTopLevel() throws {
        let request = TranslationRequest(
            text: "你好",
            source: .chinese,
            target: .english,
            model: .flash
        )

        let json = try encodeToJSON(request)

        XCTAssertEqual(json["model"] as? String, "qwen-mt-flash")
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertNotNil(json["stream_options"])

        let options = try XCTUnwrap(json["translation_options"] as? [String: Any])
        XCTAssertEqual(options["source_lang"] as? String, "Chinese")
        XCTAssertEqual(options["target_lang"] as? String, "English")

        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertEqual(messages.first?["content"] as? String, "你好")

        // Qwen-MT 不支持 system message，也不走 extra_body 包装。
        XCTAssertNil(json["extra_body"])
        XCTAssertNil(json["system"])
    }

    func testNonStreamingModelDisablesStreamFlags() throws {
        let request = TranslationRequest(
            text: "hello",
            source: .english,
            target: .chinese,
            model: .plus
        )

        let json = try encodeToJSON(request)

        XCTAssertEqual(json["stream"] as? Bool, false)
        XCTAssertNil(json["stream_options"])
    }

    private func encodeToJSON(_ request: TranslationRequest) throws -> [String: Any] {
        let data = try JSONEncoder().encode(request)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

final class TranslationStreamTests: XCTestCase {
    func testParsesSSEPayloadLines() {
        XCTAssertEqual(
            TranslationSSEEvent.parse(line: #"data: {"choices":[]}"#),
            .payload(#"{"choices":[]}"#)
        )
        XCTAssertEqual(TranslationSSEEvent.parse(line: "data:[DONE]"), .done)
    }

    func testIgnoresNonPayloadLines() {
        XCTAssertEqual(TranslationSSEEvent.parse(line: ""), .ignore)
        XCTAssertEqual(TranslationSSEEvent.parse(line: "   "), .ignore)
        XCTAssertEqual(TranslationSSEEvent.parse(line: ": keep-alive"), .ignore)
        XCTAssertEqual(TranslationSSEEvent.parse(line: "event: message"), .ignore)
        XCTAssertEqual(TranslationSSEEvent.parse(line: "data:"), .ignore)
    }

    func testDecodesStreamingDelta() throws {
        let json = #"{"choices":[{"delta":{"content":"Hello"}}]}"#
        let chunk = try JSONDecoder().decode(
            TranslationChunk.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(chunk.choices?.first?.delta?.content, "Hello")
    }

    func testDecodesWholeResponseMessage() throws {
        let json = #"{"choices":[{"message":{"content":"你好"}}]}"#
        let chunk = try JSONDecoder().decode(
            TranslationChunk.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(chunk.choices?.first?.message?.content, "你好")
    }

    func testDecodesErrorEnvelope() throws {
        let json = #"{"error":{"message":"Invalid API-key provided.","code":"invalid_api_key"}}"#
        let chunk = try JSONDecoder().decode(
            TranslationChunk.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(chunk.error?.code, "invalid_api_key")
        XCTAssertTrue(chunk.choices == nil)
    }

    func testMapsHTTPStatusToUserFacingError() {
        let unauthorized = Data(#"{"error":{"message":"Invalid API-key provided."}}"#.utf8)
        XCTAssertEqual(
            TranslationService.mapError(status: 401, data: unauthorized),
            .unauthorized("Invalid API-key provided.")
        )

        let throttled = Data(#"{"error":{"message":"Requests rate limit exceeded"}}"#.utf8)
        XCTAssertEqual(
            TranslationService.mapError(status: 429, data: throttled),
            .rateLimited("Requests rate limit exceeded")
        )

        XCTAssertEqual(
            TranslationService.mapError(status: 503, data: Data()),
            .server("")
        )
    }

    func testMapsInvalidAPIKeyCodeRegardlessOfStatus() {
        let body = Data(#"{"error":{"message":"bad key","code":"invalid_api_key"}}"#.utf8)
        XCTAssertEqual(
            TranslationService.mapError(status: 400, data: body),
            .unauthorized("bad key")
        )
    }
}

final class SelectionTextNormalizerTests: XCTestCase {
    func testTrimsAndNormalizesSpaces() {
        XCTAssertEqual(
            SelectionTextNormalizer.normalize("  hello\u{00A0}world  "),
            "hello world"
        )
        XCTAssertEqual(
            SelectionTextNormalizer.normalize("你好\u{3000}世界\n"),
            "你好 世界"
        )
    }

    func testTruncatesOverlongSelection() {
        let long = String(repeating: "a", count: 6000)
        XCTAssertEqual(
            SelectionTextNormalizer.normalize(long).count,
            SelectionTextNormalizer.maximumLength
        )
    }
}

/// AX 的 `AXSelectedTextRange` 以 UTF-16 码元为单位，按 `Character` 切会在
/// 含 emoji 的文本上偏移——这是「取到的文本比选中的多/少一截」的根源。
final class SelectionRangeSlicerTests: XCTestCase {
    func testSlicesASCII() {
        XCTAssertEqual(
            SelectionRangeSlicer.slice("hello world", location: 6, length: 5),
            "world"
        )
    }

    func testSlicesCJK() {
        // 每个汉字占 1 个 UTF-16 码元。
        XCTAssertEqual(
            SelectionRangeSlicer.slice("你好世界", location: 1, length: 2),
            "好世"
        )
    }

    func testSlicesSurrogatePairByCodeUnits() {
        // "a😀b" 的码元数是 1 + 2 + 1；emoji 单独占 2 个码元。
        XCTAssertEqual(
            SelectionRangeSlicer.slice("a😀b", location: 1, length: 2),
            "😀"
        )
    }

    func testRejectsOutOfBoundsRange() {
        XCTAssertNil(SelectionRangeSlicer.slice("abc", location: 2, length: 5))
    }

    func testRejectsEmptyAndNegativeRange() {
        XCTAssertNil(SelectionRangeSlicer.slice("abc", location: 0, length: 0))
        XCTAssertNil(SelectionRangeSlicer.slice("abc", location: -1, length: 2))
    }
}

final class TranslationNoteComposerTests: XCTestCase {
    func testComposesQuoteBlockNote() {
        let markdown = TranslationNoteComposer.markdown(
            sourceText: "  今天下雨  ",
            translatedText: "  It rains today.  "
        )

        // 引用块开头 → NoteStore 提取标题时会剥掉 "> "，标题即原文。
        XCTAssertEqual(markdown, "> 今天下雨\n\nIt rains today.")
    }
}

@MainActor
final class TranslationLayoutTests: XCTestCase {
    /// 笔记页与翻译页共用同一档展开宽度（对齐原先左右分栏所需的较宽档位），
    /// 切换工作区时面板不再伸缩。
    func testExpandedWidthUsesWideTierAndIsModeIndependent() {
        let layout = NotchGeometry.layout(for: nil)

        // 无刘海屏幕用 210pt 兜底刘海宽度：210 + 520 = 730，落在 700...760 区间内。
        XCTAssertEqual(layout.expandedSize.width, 730)
    }

    func testExpandedWidthStaysInsideNarrowScreens() {
        let layout = NotchGeometry.layout(for: nil)

        XCTAssertGreaterThanOrEqual(layout.expandedSize.width, 700)
        XCTAssertLessThanOrEqual(layout.expandedSize.width, 760)
        XCTAssertGreaterThan(layout.expandedSize.width, layout.compactSize.width)
    }
}
