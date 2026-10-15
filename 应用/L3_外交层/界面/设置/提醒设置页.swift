// 所属层级：L3 外交层（界面）
// 文件职责：编辑本地规则、模式能力与显示偏好。
// 输入：用户偏好；输出：经校验的保存命令。
// 依赖：AppModel；云端未接入时不可切换。
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var preferences = ReminderPreferences()
    @State private var loaded = false
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("提醒方式") {
                    Picker("使用方式", selection: Binding(get: { preferences.mode }, set: { mode in
                        model.attempt { try LocalCapabilities().requestMode(mode); preferences.mode = mode }
                    })) {
                        Text("本地").tag(ReminderMode.local)
                        Text("云端 · 尚未接入").tag(ReminderMode.cloud).disabled(true)
                    }
                    Text("本地按规则随机选择，不需要服务器。每次打开，补齐含今天的三个自然日。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("时间规则") {
                    Toggle("启用提醒", isOn: $preferences.enabled)
                    Picker("随机时间", selection: $preferences.timePolicy) {
                        Text("避开免打扰").tag(TimePolicy.avoidQuiet)
                        Text("全天随机").tag(TimePolicy.allDay)
                    }
                    if preferences.timePolicy == .allDay {
                        Text("任何时刻都可能提醒，包括夜间；系统专注设置仍会生效。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if preferences.timePolicy == .avoidQuiet {
                    Section("每日免打扰") {
                        ForEach($preferences.quietIntervals) { $interval in QuietIntervalRow(interval: $interval) }
                            .onDelete { preferences.quietIntervals.remove(atOffsets: $0) }
                        Button("添加时间带") {
                            preferences.quietIntervals.append(QuietInterval(startMinute: 12 * 60, endMinute: 13 * 60))
                        }
                        Text("时间带可以重叠或跨午夜。向左滑动可移除。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("琐事") {
                    Picker("每天最多", selection: $preferences.ideaDailyLimit) {
                        Text("关闭琐事提醒").tag(0)
                        Text("一条").tag(1)
                        Text("两条").tag(2)
                    }
                    Text("新记下的念头先放一天，同一条至少隔三天；没有合适的内容就不提醒。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("计划摘要") {
                    Toggle("每日回顾计划", isOn: $preferences.digestEnabled)
                    if preferences.digestEnabled { DatePicker("固定时间", selection: digestTime, displayedComponents: .hourAndMinute) }
                    Text("没有进行中的计划时不发空摘要。摘要时间需在免打扰之外。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("通知内容") {
                    Toggle("显示标题和简短摘要", isOn: $preferences.contentPreview)
                    Toggle("通知声音", isOn: $preferences.soundEnabled)
                    Text("锁屏是否显示内容仍遵循系统预览设置。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("提醒状态") {
                    LabeledContent("系统权限", value: model.permissionLabel)
                    if let time = model.pendingRows.first?.fireAt {
                        LabeledContent("下次预计", value: time.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let end = model.workspace.runtime.coverageEnd {
                        LabeledContent("本地计算到", value: end.formatted(date: .abbreviated, time: .shortened))
                    }
                    if model.workspace.runtime.omittedDeadlines > 0 {
                        Text("\(model.workspace.runtime.omittedDeadlines) 条期限提醒尚未排入，请查看各计划时间。")
                    }
                    if model.workspace.runtime.capacityLimited { Text("队列空间不足，部分提醒等待下次打开补排。") }
                    if let error = model.workspace.runtime.lastError { Text(error).font(.caption).foregroundStyle(.orange) }
                    Button("打开系统通知设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    Button("重新检查和安排") { model.queueRefresh() }
                    NavigationLink("通知检查") { NotificationDiagnosticsView() }
                }
                Section("资料与显示") {
                    NavigationLink("备份与恢复") { BackupView() }
                    Picker("外观", selection: Binding(get: { model.workspace.appearance }, set: { model.setAppearance($0) })) {
                        Text("跟随系统").tag(Appearance.system)
                        Text("浅色").tag(Appearance.light)
                        Text("深色").tag(Appearance.dark)
                    }
                }
            }
            .navigationTitle("提醒与设置").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard model.attempt({ try model.savePreferences(preferences) }) else { return }
                        saving = true
                        Task { @MainActor in
                            if preferences.enabled { await model.enableNotifications() }
                            saving = false
                            dismiss()
                        }
                    }.disabled(saving)
                }
            }
            .onAppear { if !loaded { preferences = model.preferences; loaded = true } }
            .appFeedback()
        }
    }

    private var digestTime: Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: preferences.digestMinute / 60, minute: preferences.digestMinute % 60,
                                  second: 0, of: Date()) ?? Date()
        }, set: {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
            preferences.digestMinute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        })
    }
}
