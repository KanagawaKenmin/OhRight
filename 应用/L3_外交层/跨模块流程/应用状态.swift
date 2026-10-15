// 所属层级：L3 外交层
// 文件职责：装配资料与界面状态，集中显式提交。
// 输入：L2 用例结果；输出：已保存的可观察快照。
// 依赖：仓库/通知接缝；保存失败不替换界面事实。
import Foundation
import Observation

@MainActor @Observable final class AppModel {
    var workspace: Workspace
    var path: [UUID] = []
    var readingItemID: UUID?
    var routeGeneration = 0
    var message: String?
    var notice: String?
    var permissionLabel = "正在检查"
    var isRefreshing = false
    var refreshAgain = false
    var pendingRows: [ReminderIntent] = []
    @ObservationIgnored let repository: any WorkspaceRepository
    @ObservationIgnored let delivery: LocalNotificationDelivery
    @ObservationIgnored let planner: any ReminderPlanner

    init(repository: any WorkspaceRepository, delivery: LocalNotificationDelivery,
         planner: any ReminderPlanner = LocalReminderPlanner()) throws {
        self.repository = repository
        self.delivery = delivery
        self.planner = planner
        workspace = try repository.load()
    }

    var mode: ItemKind { workspace.lastMode }
    var preferences: ReminderPreferences { workspace.preferences }
    var calendar: Calendar { Calendar.autoupdatingCurrent }

    func item(_ id: UUID) -> Item? { workspace.items.first { $0.id == id } }

    @discardableResult func attempt(_ operation: () throws -> Void) -> Bool {
        do { try operation(); return true }
        catch { message = error.localizedDescription; return false }
    }

    /// 显式事务保存成功才发布新快照；业务版本与待协调标记同次写入。
    func commit(_ candidate: Workspace, business: Bool = true, refresh: Bool = true) throws {
        var value = candidate
        if business { value.revision = workspace.revision + 1 }
        try repository.save(value)
        workspace = value
        if refresh { queueRefresh() }
    }

    func queueRefresh() { Task { await refreshNotifications() } }

    func selectMode(_ mode: ItemKind) {
        attempt {
            var next = workspace
            next.lastMode = mode
            try commit(next, business: false, refresh: false)
        }
    }

    func saveDraft(_ draft: CaptureDraft, key: String) {
        attempt {
            var next = workspace
            next.drafts[key] = draft
            try commit(next, business: false, refresh: false)
        }
    }

    func setAppearance(_ value: Appearance) {
        attempt {
            var next = workspace
            next.appearance = value
            try commit(next, business: false, refresh: false)
        }
    }

    func savePreferences(_ value: ReminderPreferences) throws {
        try ContentValidation.preferences(value)
        if value.enabled, let blocked = workspace.items.first(where: {
            $0.isRemindable && ($0.deadlineReminderAt.map { $0 > Date() && !value.allows($0, calendar: calendar) } ?? false)
        }) {
            throw DomainError.invalid("“\(blocked.title)”的期限提醒落入新免打扰时间，请先调整该计划的提醒或关闭提醒。")
        }
        var next = workspace
        next.preferences = value
        try commit(next)
    }

    func start() async {
        delivery.configure()
        let expiration = Date().addingTimeInterval(-30 * 24 * 3600)
        let old = workspace.items.count
        var next = workspace
        next.items.removeAll { $0.status == .deleted && ($0.deletedAt ?? .distantFuture) < expiration }
        if next.items.count != old { attempt { try commit(next, refresh: false) } }
        await NotificationRouter.shared.attach(self)
        await refreshNotifications()
    }
}
