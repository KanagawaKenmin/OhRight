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
    private var kind: ItemKind { model.item(itemID)?.kind ?? .idea }
    var body: some View {
        NavigationStack {
            Form {
                TextEditor(text: $draft.text).frame(minHeight: 220).accessibilityLabel("记录内容")
                PhotoAttachmentEditor(attachments: $draft.attachments, working: $importingPhoto,
                    existingCount: (model.item(itemID)?.attachments.count ?? 0) +
                        (model.item(itemID)?.entries.filter { $0.id != entry.id }.flatMap(\.attachments).count ?? 0),
                    kind: kind, format: $draft.textFormat, preview: $preview, persist: persist)
                if preview { BodyReader(source: draft.text, format: draft.textFormat) }
            }
                .scrollContentBackground(.hidden).background { ModeBackground(mode: kind) }
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
        }.tint(AppPalette.accent(kind))
    }
    private func persist() { if loaded && !saved { model.saveDraft(draft, key: draftKey) } }
}
