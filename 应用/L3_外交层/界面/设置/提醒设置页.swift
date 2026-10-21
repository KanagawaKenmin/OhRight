// 所属层级：L3 外交层（界面）
// 文件职责：设置一级导航；只展示可用的用户选项。
// 输入：应用状态；输出：分组设置导航。
// 依赖：SwiftUI、AppModel；偏好由二级页即时保存。
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { ReminderSettingsView() } label: {
                        LabeledContent("通知与提醒", value: !model.notificationAccess.allowed ? "通知未开启" :
                            model.preferences.enabled ? "开启" : "已暂停")
                    }
                    .accessibilityIdentifier("notificationSettings")
                    Picker("外观", selection: Binding(get: { model.workspace.appearance }, set: { model.setAppearance($0) })) {
                        Text("跟随系统").tag(Appearance.system)
                        Text("浅色").tag(Appearance.light)
                        Text("深色").tag(Appearance.dark)
                    }
                }
                Section {
                    NavigationLink("备份与恢复") { BackupView() }
                    NavigationLink("回收站") { LibraryContent(scope: .trash) }
                }
                Section { NavigationLink("帮助与关于") { HelpView() } }
            }
            .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .appFeedback()
        }
    }
}
