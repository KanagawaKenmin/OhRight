// 所属层级：L3 外交层（界面）
// 文件职责：以紧凑且可换行的按钮控制格式和预览。
// 输入：格式、预览绑定及模式；输出：原草稿字段变更。
// 依赖：SwiftUI、工具样式；不解析或另存正文。
import SwiftUI

struct RecordFormatTools: View {
    @Binding var format: TextFormat
    @Binding var preview: Bool
    let kind: ItemKind
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) { markdownButton; previewButton }
            VStack(alignment: .leading, spacing: 4) { markdownButton; previewButton }
        }
    }
    private var markdownButton: some View {
        Button { format = format == .markdown ? .plain : .markdown } label: {
            Text("Markdown").fixedSize(horizontal: true, vertical: true)
        }
        .buttonStyle(EditorToolStyle(kind: kind, selected: format == .markdown))
        .accessibilityLabel("Markdown 格式").accessibilityValue(format == .markdown ? "开启" : "关闭")
    }
    private var previewButton: some View {
        Button { preview.toggle() } label: {
            Label("预览", systemImage: preview ? "eye.fill" : "eye").fixedSize(horizontal: true, vertical: true)
        }
        .buttonStyle(EditorToolStyle(kind: kind, selected: preview))
        .accessibilityLabel("预览").accessibilityValue(preview ? "开启" : "关闭")
    }
}
