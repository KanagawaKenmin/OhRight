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
    @State private var draft = CaptureDraft()
    @State private var preview = false
    @State private var loaded = false
    @State private var saved = false
    @State private var importingPhoto = false
    private var draftKey: String { "entryEdit/\(itemID)/\(entry.id)" }
    var body: some View {
        NavigationStack {
            Form {
                TextEditor(text: $draft.text).frame(minHeight: 220).accessibilityLabel("记录内容")
                Toggle("Markdown 格式", isOn: Binding(get: { draft.textFormat == .markdown },
                    set: { draft.textFormat = $0 ? .markdown : .plain }))
                Toggle("预览", isOn: $preview)
                if preview { BodyReader(source: draft.text, format: draft.textFormat) }
                PhotoAttachmentEditor(attachments: $draft.attachments, working: $importingPhoto,
                    existingCount: (model.item(itemID)?.attachments.count ?? 0) +
                        (model.item(itemID)?.entries.filter { $0.id != entry.id }.flatMap(\.attachments).count ?? 0),
                    persist: persist)
            }
                .navigationTitle("修正记录").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(importingPhoto) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            if model.attempt({ try model.saveEntryEdit(itemID, entryID: entry.id, draft: draft, draftKey: draftKey) }) {
                                saved = true; dismiss()
                            }
                        }.disabled(importingPhoto)
                    }
                }.onAppear {
                    guard !loaded else { return }
                    draft = model.workspace.drafts[draftKey] ?? CaptureDraft(text: entry.text,
                        textFormat: entry.textFormat, attachments: entry.attachments)
                    loaded = true
                }
                .onChange(of: draft) { _, _ in persist() }
                .onDisappear { persist() }.interactiveDismissDisabled(importingPhoto).appFeedback()
        }
    }
    private func persist() { if loaded && !saved { model.saveDraft(draft, key: draftKey) } }
}
