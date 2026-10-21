// 所属层级：L0 公理层
// 文件职责：定义通知权限与首次引导的确定性决策。
// 输入：系统权限、引导标记；输出：是否请求及允许后的偏好。
// 依赖：Foundation；权限事实始终由系统重新查询。
import Foundation

enum NotificationAccess: Equatable, Sendable {
    case unknown, notDetermined, denied, allowed, quiet
    var allowed: Bool { self == .allowed || self == .quiet }
    var label: String {
        switch self {
        case .unknown: "正在检查"
        case .notDetermined, .denied: "通知未开启"
        case .allowed: "已开启"
        case .quiet: "横幅未开启"
        }
    }
}

enum NotificationOnboardingRule {
    static func needsRequest(_ access: NotificationAccess) -> Bool { access == .notDetermined }

    /// 旧安装与已主动选择的用户仅显示操作，不静默改写偏好。
    static func completed(_ original: Workspace, access: NotificationAccess) -> Workspace {
        var next = original
        let onboarding = original.notificationOnboarding
        if access.allowed && onboarding.version == 0 {
            if onboarding.isNewInstallation && !onboarding.userChoseReminder {
                next.preferences.enabled = true
            } else if !next.preferences.enabled && !onboarding.userChoseReminder {
                next.notificationOnboarding.offerEnable = true
            }
        }
        next.notificationOnboarding.version = 1
        return next
    }
}
