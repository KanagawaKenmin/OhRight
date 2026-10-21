// 所属层级：L3 外交层（界面）
// 文件职责：将共用安全文字片段渲染为有限 Markdown。
// 输入：源文、格式；输出：可选中、只允许 http(s) 的阅读内容。
// 依赖：ReadableText；编辑页始终保留原文。
import SwiftUI

struct BodyReader: View {
    let source: String
    var format: TextFormat = .plain
    var body: some View {
        Text(attributed).textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                ["http", "https"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded
            })
    }
    private var attributed: AttributedString {
        var result = AttributedString()
        for span in ReadableText.spans(source, format: format) {
            var part = AttributedString(span.text)
            var font = Font.body
            if span.bold { font = font.bold() }
            if span.italic { font = font.italic() }
            if span.code { font = font.monospaced() }
            part.font = font
            if let link = span.link { part.link = link }
            result.append(part)
        }
        return result
    }
}
