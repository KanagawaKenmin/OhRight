// 所属层级：L3 外交层（界面）
// 文件职责：一句话输入、计划字段与自动保存草稿。
// 输入：类别、可选原事项；输出：用户提交命令。
// 依赖：AppModel；关闭保留草稿，保存成功才退出。
import SwiftUI

struct ItemEditorView: View {
    let kind: ItemKind
    var itemID: UUID?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var draft = CaptureDraft()
    @State private var loaded = false
    @State private var saved = false
    @State private var savingTask: Task<Void, Never>?
    @State private var preview = false
    @State private var importingPhoto = false
    @FocusState private var focused: Bool

    private var draftKey: String { itemID.map { "edit/\($0)/\(kind.rawValue)" } ?? "capture/\(kind.rawValue)" }
    private var isConversion: Bool { itemID.flatMap { model.item($0) }?.kind == .idea && kind == .plan }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(kind == .idea ? "突然想到什么？" : "打算完成什么？", text: $draft.text, axis: .vertical)
                        .lineLimit(5...14).focused($focused).font(.body)
                        .accessibilityIdentifier("itemText")
                    Text("第一行作为标题；没想完整也可以保存。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Toggle("Markdown 格式", isOn: Binding(get: { draft.textFormat == .markdown },
                        set: { draft.textFormat = $0 ? .markdown : .plain }))
                    Toggle("预览", isOn: $preview)
                    if preview {
                        let lines = draft.text.components(separatedBy: "\n")
                        Text(lines.first ?? "").font(.headline)
                        BodyReader(source: lines.dropFirst().joined(separator: "\n"), format: draft.textFormat)
                    }
                }
                Section("图片") {
                    PhotoAttachmentEditor(attachments: $draft.attachments, working: $importingPhoto,
                        existingCount: itemID.flatMap { model.item($0) }?.entries.flatMap(\.attachments).count ?? 0,
                        persist: persistDraft)
                }
                if kind == .plan { planFields }
                Section("可选") {
                    EffortSlider(minutes: $draft.effortMinutes)
                }
                if itemID == nil, model.workspace.drafts[draftKey] != nil {
                    Section { Text("输入会自动保留为草稿。关闭后下次可继续。")
                        .font(.caption).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(isConversion ? "转为计划" : itemID == nil ? (kind == .idea ? "记一下" : "新计划") : "编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { persistDraft(); dismiss() }.disabled(importingPhoto) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        savingTask?.cancel()
                        if model.attempt({ try model.saveItem(draft: draft, kind: kind, existingID: itemID, draftKey: draftKey) }) {
                            saved = true
                            dismiss()
                        }
                    }.fontWeight(.semibold).accessibilityIdentifier("saveItem").disabled(importingPhoto)
                }
            }
            .onAppear {
                guard !loaded else { return }
                if let stored = model.workspace.drafts[draftKey] { draft = stored }
                else if let id = itemID, let item = model.item(id) { draft = ItemEditing.draft(for: item) }
                loaded = true
                focused = itemID == nil
            }
            .onChange(of: draft) { _, _ in
                guard loaded && !saved else { return }
                savingTask?.cancel()
                savingTask = Task { @MainActor in
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                    persistDraft()
                }
            }
            .onChange(of: phase) { _, state in if state != .active { persistDraft() } }
            .onDisappear { savingTask?.cancel(); persistDraft() }
            .interactiveDismissDisabled(importingPhoto)
            .appFeedback()
        }.tint(AppPalette.accent(kind))
    }

    private var planFields: some View {
        Group {
            Section("截止") {
                Toggle("指定具体时间", isOn: $draft.hasExactTime)
                DatePicker("截止日期", selection: $draft.dueDate,
                           displayedComponents: draft.hasExactTime ? [.date, .hourAndMinute] : [.date])
                    .environment(\.timeZone, itemID.flatMap { model.item($0)?.deadline?.calendar.timeZone } ?? .autoupdatingCurrent)
                Text(draft.hasExactTime ? "按这个具体时刻截止。" : "当天结束前完成。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("下一小步") {
                TextField("例如：找出去年版本", text: $draft.nextAction, axis: .vertical).lineLimit(2...5)
            }
            Section("一次期限提醒") {
                Toggle("另外提醒一次", isOn: Binding(get: { draft.deadlineReminderAt != nil }, set: { enabled in
                    let suggestion = draft.dueDate.addingTimeInterval(-24 * 3600)
                    draft.deadlineReminderAt = enabled ? max(Date().addingTimeInterval(3600), suggestion) : nil
                }))
                if let date = draft.deadlineReminderAt {
                    DatePicker("提醒时间", selection: Binding(get: { draft.deadlineReminderAt ?? date },
                                                          set: { draft.deadlineReminderAt = $0 }))
                    if !model.preferences.allows(date, calendar: model.calendar) {
                        Text("这个时间在免打扰内，可以选择更早的允许时间。")
                            .font(.caption).foregroundStyle(.orange)
                        Button("使用更早的允许时间") {
                            var candidate = date
                            for _ in 0..<(8 * 25 * 60) {
                                candidate = candidate.addingTimeInterval(-60)
                                if model.preferences.allows(candidate, calendar: model.calendar) {
                                    draft.deadlineReminderAt = candidate
                                    return
                                }
                            }
                            model.message = "没有找到允许的提醒时间，请调整免打扰。"
                        }
                    }
                    Text("提醒必须在现在之后、截止之前。窗口外会在下次打开时补排。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func persistDraft() {
        guard loaded && !saved else { return }
        model.saveDraft(draft, key: draftKey)
    }
}
