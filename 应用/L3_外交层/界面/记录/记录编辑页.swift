// 所属层级：L3 外交层（界面）
// 文件职责：修正误记的时间线文字，保留上一个版本。
// 输入：事项/记录编号；输出：更新命令。
// 依赖：AppModel、PlanProgress；不更改原记录发生时间。
import SwiftUI

struct EntryEditorView: View {
    let itemID: UUID
    let entry: ItemEntry
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    var body: some View {
        NavigationStack {
            Form { TextEditor(text: $text).frame(minHeight: 220).accessibilityLabel("记录内容") }
                .navigationTitle("修正记录").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            if model.attempt({ try model.transformItem(itemID) {
                                try PlanProgress.editEntry(in: $0, entryID: entry.id, text: text, now: Date())
                            } }) { dismiss() }
                        }
                    }
                }.onAppear { text = entry.text }.appFeedback()
        }
    }
}
