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
    var diagnosticError: String?
    var notice: String?
    var undoItem: ItemUndo?
    var permissionLabel = "正在检查"
    var notificationAccess: NotificationAccess = .unknown
    var onboardingInProgress = false
    var hasStarted = false
    var isRefreshing = false
    var refreshAgain = false
    var pendingRows: [ReminderIntent] = []
    @ObservationIgnored let repository: any WorkspaceRepository
    @ObservationIgnored let delivery: any NotificationService
    @ObservationIgnored let planner: any ReminderPlanner
    @ObservationIgnored let attachments: AttachmentStore

    init(repository: any WorkspaceRepository, delivery: any NotificationService,
         planner: any ReminderPlanner = LocalReminderPlanner(), attachmentStore: AttachmentStore? = nil) throws {
        self.repository = repository
        self.delivery = delivery
        self.planner = planner
        if let attachmentStore { self.attachments = attachmentStore }
        else {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true).appendingPathComponent("Attachments", isDirectory: true)
            self.attachments = try AttachmentStore(root: root)
        }
        workspace = try repository.load()
    }

    var mode: ItemKind { workspace.lastMode }
    var preferences: ReminderPreferences { workspace.preferences }
    var calendar: Calendar { Calendar.autoupdatingCurrent }

    func item(_ id: UUID) -> Item? { workspace.items.first { $0.id == id } }

    @discardableResult func attempt(_ operation: () throws -> Void) -> Bool {
        do { try operation(); return true }
        catch { report(error); return false }
    }

    /// 正常页面只给可执行的领域提示，原始错误保留给故障排查。
    func report(_ error: any Error) {
        if !(error is DomainError) { diagnosticError = error.localizedDescription }
        message = (error as? DomainError)?.errorDescription ?? "操作未能完成，请稍后重试。"
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

    func clearDraft(_ key: String) {
        guard workspace.drafts[key] != nil else { return }
        attempt {
            var next = workspace
            next.drafts.removeValue(forKey: key)
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
        if value.enabled != preferences.enabled {
            next.notificationOnboarding.userChoseReminder = true
            next.notificationOnboarding.offerEnable = false
        }
        do { try commit(next) }
        catch { diagnosticError = error.localizedDescription; throw DomainError.invalid("设置未能保存，请稍后重试。") }
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        delivery.configure()
        let expiration = Date().addingTimeInterval(-30 * 24 * 3600)
        let old = workspace.items.count
        var next = workspace
        let expiredIDs = Set(next.items.filter { $0.status == .deleted && ($0.deletedAt ?? .distantFuture) < expiration }.map(\.id))
        next.items.removeAll { $0.status == .deleted && ($0.deletedAt ?? .distantFuture) < expiration }
        next.removeDrafts(for: expiredIDs)
        if next.items.count != old { attempt { try commit(next, refresh: false) } }
        do { try attachments.collect(referenced: workspace.allAttachments) }
        catch { message = "图片清理暂未完成，现有记录仍可使用。" }
        await NotificationRouter.shared.attach(self)
        await refreshNotifications()
    }
}

extension Workspace {
    /// 永久清理只移除对应事项的编辑草稿，其他捕获草稿保持可恢复。
    mutating func removeDrafts(for ids: Set<UUID>) {
        drafts = drafts.filter { key, _ in
            !ids.contains { key == "entry/\($0)" || key.hasPrefix("edit/\($0)/") || key.hasPrefix("entryEdit/\($0)/") }
        }
    }
}
