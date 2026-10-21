// 所属层级：L3 外交层
// 文件职责：在首页前台且无其他弹窗时协调一次系统授权与兼容引导。
// 输入：界面可交互事件；输出：系统授权和已持久化引导标记。
// 依赖：UIKit、纯规则、通知适配器；重入不创建并行请求。
import UIKit

extension AppModel {
    func prepareNotificationOnboarding() async {
        guard !onboardingInProgress, UIApplication.shared.applicationState == .active else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitest") { return }
        #endif
        let controllers = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).filter(\.isKeyWindow).compactMap(\.rootViewController)
        guard !controllers.contains(where: { $0.presentedViewController != nil }) else { return }
        onboardingInProgress = true
        defer { onboardingInProgress = false }
        do {
            var access = await delivery.access()
            if NotificationOnboardingRule.needsRequest(access) {
                _ = try await delivery.requestPermission()
                access = await delivery.access()
            }
            // 系统弹窗期间用户可能保存了偏好，必须以返回后的最新快照为基准。
            let next = NotificationOnboardingRule.completed(workspace, access: access)
            if next != workspace { try commit(next) }
            await refreshNotifications()
        } catch { message = "通知设置暂时无法保存，请稍后重试。" }
    }
}
