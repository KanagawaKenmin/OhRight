// 所属层级：L3 外交层（界面）
// 文件职责：即时保存单项提醒设置，时间编辑交给子页事务。
// 输入：控件修改；输出：校验提交或原值回显。
// 依赖：AppModel；每次使用最新偏好，避免连续修改互相覆盖。
import SwiftUI
import UIKit

struct ReminderSettingsView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Form {
            Section("提醒") {
                Toggle("允许提醒", isOn: binding(\.enabled))
                if !model.notificationAccess.allowed {
                    Text("通知未开启").foregroundStyle(.secondary)
                    if model.notificationAccess == .notDetermined {
                        Button("开启通知") { Task { await model.requestNotificationAccess() } }
                    } else { Button("前往设置") { openNotificationSettings() } }
                }
            }
            Section("琐事") {
                Picker("每天提醒", selection: binding(\.ideaDailyLimit)) {
                    Text("关闭").tag(0)
                    Text("最多 1 次").tag(1)
                    Text("最多 2 次").tag(2)
                }
            }
            Section("计划") {
                Toggle("每日回顾", isOn: binding(\.digestEnabled))
                if model.preferences.digestEnabled {
                    NavigationLink { ReminderTimeEditor(editQuiet: false) } label: {
                        LabeledContent("回顾时间", value: clock(model.preferences.digestMinute))
                    }
                }
            }
            Section("时间") {
                NavigationLink { ReminderTimeEditor(editQuiet: true) } label: {
                    LabeledContent("免打扰时段", value: model.preferences.timePolicy == .allDay ? "关闭" : "已开启")
                }
                if model.preferences.timePolicy == .allDay { Text("夜间也可能收到提醒。").font(.caption).foregroundStyle(.secondary) }
            }
            Section("通知") {
                Toggle("显示内容", isOn: binding(\.contentPreview))
                Toggle("声音", isOn: binding(\.soundEnabled))
            }
            Section("系统") {
                Button("iPhone 通知设置") { openNotificationSettings() }
                if model.notificationAccess == .quiet { Text("横幅未开启，可在 iPhone 通知设置中调整。").font(.caption) }
            }
            if model.workspace.runtime.capacityLimited || model.workspace.runtime.omittedDeadlines > 0 {
                Section { NavigationLink("部分提醒暂未安排") { ReminderHelpView() } }
            }
        }
        .navigationTitle("通知与提醒").navigationBarTitleDisplayMode(.inline)
        .task { await model.refreshNotifications() }.appFeedback()
    }

    private func binding<T>(_ key: WritableKeyPath<ReminderPreferences, T>) -> Binding<T> {
        Binding(get: { model.preferences[keyPath: key] }, set: { value in
            var next = model.preferences
            next[keyPath: key] = value
            if model.attempt({ try model.savePreferences(next) }), next.enabled,
               model.notificationAccess == .notDetermined {
                Task { await model.requestNotificationAccess() }
            }
        })
    }
}

func clock(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }

@MainActor func openNotificationSettings() {
    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
}
