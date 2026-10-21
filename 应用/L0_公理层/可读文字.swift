// 所属层级：L0 公理层
// 文件职责：定义有限 Markdown 的可读语义；不识别的语法保留原文。
// 输入：源文字和格式；输出：安全文字片段与纯文本。
// 依赖：Foundation；不解析 HTML、远程图片或非 http(s) 链接。
import Foundation

struct TextSpan: Equatable, Sendable {
    var text: String
    var bold = false
    var italic = false
    var code = false
    var link: URL?
}

enum ReadableText {
    static func plain(_ source: String, format: TextFormat) -> String {
        spans(source, format: format).map(\.text).joined()
    }

    /// 编辑源文不经过这里；只为阅读与搜索生成有限格式片段。
    static func spans(_ source: String, format: TextFormat) -> [TextSpan] {
        guard format == .markdown else { return [TextSpan(text: source)] }
        var result: [TextSpan] = []
        var fence: String?
        let lines = source.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            if index > 0 { result.append(TextSpan(text: "\n")) }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = String(trimmed.prefix(3))
                if fence == marker { fence = nil } else if fence == nil { fence = marker }
                result.append(TextSpan(text: line))
            } else if fence != nil { result.append(TextSpan(text: line)) }
            else if ["- ", "* ", "+ "].contains(where: { line.hasPrefix($0) }) {
                result.append(TextSpan(text: "• "))
                result += inline(String(line.dropFirst(2)))
            } else { result += inline(line) }
        }
        return result
    }

    private static func inline(_ source: String, depth: Int = 0) -> [TextSpan] {
        guard depth < 8 else { return [TextSpan(text: source)] }
        var result: [TextSpan] = []
        var rest = source[...]
        func raw(_ text: String) { result.append(TextSpan(text: text)) }
        while !rest.isEmpty {
            // 图片/HTML 整段保留，绝不产生资源请求；也不误把图片当成链接。
            if rest.hasPrefix("!["), let end = rest.range(of: ")") {
                raw(String(rest[..<end.upperBound])); rest = rest[end.upperBound...]; continue
            }
            if rest.first == "<", let end = rest.firstIndex(of: ">") {
                let next = rest.index(after: end)
                raw(String(rest[..<next])); rest = rest[next...]; continue
            }
            if rest.first == "\\", rest.count > 1 {
                let after = rest.index(after: rest.startIndex)
                if "\\`*_[]".contains(rest[after]) {
                    raw(String(rest[after])); rest = rest[rest.index(after: after)...]; continue
                }
            }
            if rest.first == "[", let middle = rest.range(of: "]("),
               let end = rest[middle.upperBound...].firstIndex(of: ")") {
                let destination = String(rest[middle.upperBound..<end])
                let next = rest.index(after: end)
                if let url = URL(string: destination), let scheme = url.scheme?.lowercased(),
                   ["https", "http"].contains(scheme), url.host?.isEmpty == false {
                    let label = String(rest[rest.index(after: rest.startIndex)..<middle.lowerBound])
                    var spans = inline(label, depth: depth + 1)
                    for i in spans.indices { spans[i].link = url }
                    result += spans
                } else { raw(String(rest[..<next])) }
                rest = rest[next...]; continue
            }
            var matched = false
            for marker in ["`", "**", "__", "*", "_"] where rest.hasPrefix(marker) {
                let start = rest.index(rest.startIndex, offsetBy: marker.count)
                // 单词内部的下划线与没有配对的标记保持原样。
                if marker.contains("_"), result.last?.text.last?.isLetter == true { continue }
                guard let end = rest[start...].range(of: marker), end.lowerBound > start else { continue }
                let content = String(rest[start..<end.lowerBound])
                var spans = marker == "`" ? [TextSpan(text: content, code: true)] : inline(content, depth: depth + 1)
                for i in spans.indices {
                    if marker.count == 2 { spans[i].bold = true }
                    else if marker != "`" { spans[i].italic = true }
                }
                result += spans
                rest = rest[end.upperBound...]; matched = true; break
            }
            if matched { continue }
            raw(String(rest.removeFirst()))
        }
        // 合并相邻同样式片段，避免普通长文本产生数万个 UI 节点。
        return result.reduce(into: [TextSpan]()) { spans, span in
            if let last = spans.last, last.bold == span.bold, last.italic == span.italic,
               last.code == span.code, last.link == span.link {
                spans[spans.count - 1].text += span.text
            } else { spans.append(span) }
        }
    }
}
