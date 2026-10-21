// 测试边界：验证有限语法、安全链接、旧纯文本与源文不变。
// 输入：原始文字；输出：阅读/搜索所用的可读文字。
// 不访问网络，不使用简单正则删符号。
import Foundation
import XCTest
#if canImport(OhRightCore)
@testable import OhRightCore
#else
@testable import OhRight
#endif

final class TextFormatTests: XCTestCase {
    func testFiniteFormattingAndLists() {
        let text = "**加粗** *斜体* `代码`\n- 第一项\n1. 第二项"
        let spans = ReadableText.spans(text, format: .markdown)
        XCTAssertEqual(spans.map(\.text).joined(), "加粗 斜体 代码\n• 第一项\n1. 第二项")
        XCTAssertTrue(spans.contains { $0.text == "加粗" && $0.bold })
        XCTAssertTrue(spans.contains { $0.text == "斜体" && $0.italic })
        XCTAssertTrue(spans.contains { $0.text == "代码" && $0.code })
    }
    func testLegacyPlainAndUnsupportedSyntaxRemainLiteral() {
        let plain = "file_name_value *星号* **不闭合"
        XCTAssertEqual(ReadableText.plain(plain, format: .plain), plain)
        XCTAssertEqual(ReadableText.plain("file_name_value", format: .markdown), "file_name_value")
        let unsupported = "```swift\n**literal**\n```\n# 标题\n![图](https://example.com/a.png)\n<b>文字</b>"
        XCTAssertEqual(ReadableText.plain(unsupported, format: .markdown), unsupported)
    }
    func testOnlyExplicitHTTPLinksCanOpen() {
        let good = ReadableText.spans("[网站](https://example.com/path)", format: .markdown)
        XCTAssertEqual(good.map(\.text).joined(), "网站")
        XCTAssertEqual(good.first?.link?.scheme, "https")
        for text in ["[坏](javascript:alert)", "[文件](file:///private/a)", "[相对](../a)", "[空](https:)"] {
            let spans = ReadableText.spans(text, format: .markdown)
            XCTAssertEqual(spans.map(\.text).joined(), text)
            XCTAssertTrue(spans.allSatisfy { $0.link == nil })
        }
    }
    func testDraftSourceAndPreviousFormatSurviveEditing() throws {
        let text = "题目\n**原始正文**  \n"
        var item = try ItemEditing.create(draft: CaptureDraft(text: text), kind: .idea, now: Samples.now, timeZone: .gmt)
        XCTAssertEqual(ItemEditing.draft(for: item).text, text)
        item = try ItemEditing.appendThought(to: item, text: "*记录*", now: Samples.now, format: .markdown)
        let entry = try XCTUnwrap(item.entries.last)
        let edited = try PlanProgress.editEntry(in: item, entryID: entry.id, text: "_字面_", now: Samples.now, format: .plain)
        XCTAssertEqual(edited.entries.last?.previousText, "*记录*")
        XCTAssertEqual(edited.entries.last?.previousFormat, .markdown)
        XCTAssertEqual(edited.entries.last?.textFormat, .plain)
        XCTAssertTrue(BackupCodec.markdown(Samples.workspace([item])).contains("**原始正文**"))
    }
}
