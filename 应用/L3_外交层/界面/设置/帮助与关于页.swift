// 所属层级：L3 外交层（界面）
// 文件职责：呈现提醒限制、测试通知和独立故障排查入口。
// 输入：用户帮助操作；输出：说明与测试结果。
// 依赖：通知协调；测试不改 App 长期提醒开关。
import SwiftUI

struct HelpView: View {
    @Environment(AppModel.self) private var model
    @State private var sending = false
    var body: some View {
        Form {
            Section {
                NavigationLink("提醒帮助") { ReminderHelpView() }
                Button("发送测试通知") {
                    sending = true
                    Task { @MainActor in
                        do {
                            try await model.delivery.testNotification(sound: model.preferences.soundEnabled)
                            model.notice = "两分钟后发送，请锁屏等待。"
                        } catch { model.report(error) }
                        await model.refreshNotifications()
                        sending = false
                    }
                }.disabled(sending)
                if model.notificationAccess == .denied { Button("前往设置") { openNotificationSettings() } }
                NavigationLink("故障排查") { NotificationDiagnosticsView() }
            }
            Section { LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.3.0") }
        }.navigationTitle("帮助与关于").appFeedback()
    }
}

struct ReminderHelpView: View {
    var body: some View {
        List {
            Text("提醒会在打开 App 时更新。连续几天未打开，提醒可能暂停。")
            Text("新建或补充后的琐事，24 小时内不会提醒。同一条琐事至少间隔 3 天。没有合适的内容时不会发送。")
            Text("免打扰时段作用于所有提醒。全天随机包括夜间。")
            Text("关闭声音后仍可显示通知。横幅、锁屏预览和专注模式由 iPhone 设置控制。")
            Text("本地只安排含今天的三个自然日。窗口以外的期限提醒与容量不足的提醒会在下次打开时重新安排。")
        }.navigationTitle("提醒帮助")
    }
}
