// 所属层级：L3 外交层（界面）
// 文件职责：展示原始内容、补充/进度和生命周期操作。
// 输入：稳定事项编号；输出：应用命令与编辑导航。
// 依赖：AppModel；始终读取最新资料，处理旧通知目标。
import SwiftUI

struct ItemDetailView: View {
    let id: UUID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editorKind: ItemKind?
    @State private var entryDraft = CaptureDraft()
    @State private var entryPreview = false
    @State private var importingPhoto = false
    @State private var editingEntry: ItemEntry?
    @State private var confirmPermanent = false

    var body: some View {
        Group {
            if let item = model.item(id) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header(item)
                        if item.status != .deleted {
                            if item.kind == .plan { ChecklistView(itemID: id) }
                            VStack(alignment: .leading, spacing: 12) {
                                Text(item.kind == .idea ? "又想到一点" : "记下这次进展").font(.headline)
                                TextField(item.kind == .idea ? "补一句就好…" : "完成了什么，或卡在哪里？", text: $entryDraft.text, axis: .vertical)
                                    .lineLimit(3...8).padding(14).background(.background, in: RoundedRectangle(cornerRadius: 12))
                                Button(item.kind == .idea ? "添加记录" : "保存进展") {
                                    if model.attempt({ try model.appendDraft(id, draft: entryDraft) }) { entryDraft = CaptureDraft() }
                                }.buttonStyle(.borderedProminent).foregroundStyle(Color("OnAccent"))
                                    .disabled(importingPhoto || entryDraft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                Toggle("Markdown 格式", isOn: Binding(get: { entryDraft.textFormat == .markdown },
                                    set: { entryDraft.textFormat = $0 ? .markdown : .plain }))
                                Toggle("预览", isOn: $entryPreview)
                                if entryPreview { BodyReader(source: entryDraft.text, format: entryDraft.textFormat) }
                                PhotoAttachmentEditor(attachments: $entryDraft.attachments, working: $importingPhoto,
                                    existingCount: item.attachments.count + item.entries.flatMap(\.attachments).count,
                                    persist: persistEntry)
                            }
                            lifecycleButtons(item)
                        } else {
                            Button("从回收站恢复") { model.attempt { try model.lifecycle(id, action: .restore) } }
                            Button("永久删除", role: .destructive) { confirmPermanent = true }
                        }
                        Text("记录").font(.headline)
                        ForEach(item.entries.sorted { $0.createdAt > $1.createdAt }) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    if entry.kind != .change && item.status != .deleted {
                                        Button("编辑") { editingEntry = entry }.font(.caption).frame(minHeight: 44)
                                    }
                                }
                                BodyReader(source: entry.text, format: entry.textFormat)
                                AttachmentGallery(attachments: entry.attachments)
                                if let previous = entry.previousText {
                                    DisclosureGroup("上个版本") {
                                        BodyReader(source: previous, format: entry.previousFormat ?? .plain)
                                        AttachmentGallery(attachments: entry.previousAttachments)
                                    }
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).itemCard(item.kind)
                        }
                    }.padding(20)
                }
                .background { ModeBackground(mode: item.kind) }
                .navigationTitle(item.kind.label).navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(importingPhoto)
                .toolbar {
                    if item.status != .deleted {
                        Menu {
                            Button("编辑内容") { editorKind = item.kind }
                            if item.kind == .idea && item.status == .active {
                                Button("转为计划") { editorKind = .plan }
                                Button("先放七天") { model.attempt { try model.mute(id, permanently: false) } }
                            }
                            Button(item.reminderEnabled ? "关闭这条提醒" : "允许这条提醒") {
                                model.attempt { try model.mute(id, permanently: true) }
                            }
                            if item.mutedUntil != nil { Button("结束暂放") { model.attempt { try model.unmute(id) } } }
                            Button("归档") { model.attempt { try model.quickAction(id, action: .archive) } }
                            Button("移入回收站", role: .destructive) { model.attempt { try model.quickAction(id, action: .delete) } }
                        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                            .accessibilityLabel("事项操作").disabled(importingPhoto)
                    }
                }
                .onAppear { model.readingItemID = id; entryDraft = model.workspace.drafts["entry/\(id)"] ?? CaptureDraft() }
                .onDisappear { if model.readingItemID == id { model.readingItemID = nil } }
                .onChange(of: entryDraft) { _, value in
                    persistEntry()
                }
            } else {
                ContentUnavailableView("这条内容已不在这里", systemImage: "tray", description: Text("可以返回看看其他念头。"))
            }
        }
        .sheet(item: $editorKind) { ItemEditorView(kind: $0, itemID: id) }
        .sheet(item: $editingEntry) { EntryEditorView(itemID: id, entry: $0) }
        .confirmationDialog("永久删除后只能从外部备份找回。", isPresented: $confirmPermanent, titleVisibility: .visible) {
            Button("永久删除", role: .destructive) {
                if model.attempt({ try model.permanentlyDelete(id) }) { dismiss() }
            }
        }
        .appFeedback()
    }

    private func header(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.title).font(.largeTitle.weight(item.kind == .idea ? .medium : .bold)).textSelection(.enabled)
                .accessibilityIdentifier("itemDetailTitle")
            if !item.body.isEmpty { BodyReader(source: item.body, format: item.textFormat) }
            AttachmentGallery(attachments: item.attachments)
            if let due = item.deadline {
                Label("\(due.label) · \(due.timeZoneID)", systemImage: "calendar").font(.subheadline).foregroundStyle(.secondary)
                if due.boundary <= Date() && item.status == .active { Text("已经过期，可以继续、改期，或先归档。").font(.caption) }
            }
            Text(item.status.label).font(.caption.weight(.semibold)).foregroundStyle(AppPalette.accent(item.kind))
            if item.kind == .idea && item.status == .active {
                Button("转为计划", systemImage: "calendar.badge.plus") { editorKind = .plan }
                    .buttonStyle(.bordered).frame(minHeight: 44)
            }
            if !item.nextAction.isEmpty { Text("下一步：\(item.nextAction)").font(.headline) }
            if let until = item.mutedUntil, until > Date() { Text("暂放到 \(until.formatted(date: .abbreviated, time: .omitted))").font(.caption) }
            if !item.reminderEnabled { Text("这条内容已关闭提醒。").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func lifecycleButtons(_ item: Item) -> some View {
        HStack {
            if [.completed, .archived].contains(item.status) {
                Button("重新开始") { model.attempt { try model.lifecycle(id, action: .reopen) } }
            } else {
                Button("做到了") { model.attempt { try model.lifecycle(id, action: .complete) } }.buttonStyle(.bordered)
                if item.kind == .plan {
                    Button(item.status == .paused ? "恢复计划" : "先暂停") {
                        model.attempt { try model.lifecycle(id, action: item.status == .paused ? .resume : .pause) }
                    }
                }
            }
        }
    }

    private func persistEntry() {
        let key = "entry/\(id)"
        if entryDraft.text.isEmpty && entryDraft.attachments.isEmpty { model.clearDraft(key) }
        else { model.saveDraft(entryDraft, key: key) }
    }
}
