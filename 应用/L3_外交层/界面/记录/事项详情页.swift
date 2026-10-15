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
    @State private var entryText = ""
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
                                TextField(item.kind == .idea ? "补一句就好…" : "完成了什么，或卡在哪里？", text: $entryText, axis: .vertical)
                                    .lineLimit(3...8).padding(14).background(.background, in: RoundedRectangle(cornerRadius: 12))
                                Button(item.kind == .idea ? "留下这点想法" : "保存进展") {
                                    if model.attempt({ try model.append(id, text: entryText) }) { entryText = "" }
                                }.buttonStyle(.borderedProminent).foregroundStyle(Color("OnAccent"))
                                    .disabled(entryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            lifecycleButtons(item)
                        } else {
                            Button("从回收站恢复") { model.attempt { try model.lifecycle(id, action: .restore) } }
                            Button("永久删除", role: .destructive) { confirmPermanent = true }
                        }
                        Text("留下的痕迹").font(.headline)
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
                                Text(entry.text).textSelection(.enabled)
                                if let previous = entry.previousText {
                                    DisclosureGroup("上个版本") { Text(previous).font(.subheadline).textSelection(.enabled) }
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).itemCard(item.kind)
                        }
                    }.padding(20)
                }
                .background { ModeBackground(mode: item.kind) }
                .navigationTitle(item.kind.label).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if item.status != .deleted {
                        Menu {
                            Button("编辑内容") { editorKind = item.kind }
                            if item.kind == .idea {
                                Button("转为计划") { editorKind = .plan }
                                Button("先放七天") { model.attempt { try model.mute(id, permanently: false) } }
                            }
                            Button(item.reminderEnabled ? "关闭这条提醒" : "允许这条提醒") {
                                model.attempt { try model.mute(id, permanently: true) }
                            }
                            if item.mutedUntil != nil { Button("结束暂放") { model.attempt { try model.unmute(id) } } }
                            Button("不打算做了，归档") { model.attempt { try model.lifecycle(id, action: .archive) } }
                            Button("移入回收站", role: .destructive) { model.attempt { try model.lifecycle(id, action: .delete) } }
                        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("事项操作")
                    }
                }
                .onAppear { model.readingItemID = id; entryText = model.workspace.drafts["entry/\(id)"]?.text ?? "" }
                .onDisappear { if model.readingItemID == id { model.readingItemID = nil } }
                .onChange(of: entryText) { _, value in model.saveDraft(CaptureDraft(text: value), key: "entry/\(id)") }
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
            if !item.body.isEmpty { Text(item.body).textSelection(.enabled) }
            if let due = item.deadline {
                Label("\(due.label) · \(due.timeZoneID)", systemImage: "calendar").font(.subheadline).foregroundStyle(.secondary)
                if due.boundary <= Date() && item.status == .active { Text("已经过期，可以继续、改期，或先归档。").font(.caption) }
            }
            Text(item.status.label).font(.caption.weight(.semibold)).foregroundStyle(AppPalette.accent(item.kind))
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
}
