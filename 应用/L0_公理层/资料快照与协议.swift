// 所属层级：L0 公理层
// 文件职责：定义整库快照、草稿与本地使用的接缝。
// 主要输入：领域内容；输出：仓库/排程/投递协议。
// 依赖：Foundation 与同层类型；禁止直接访问系统框架。
import Foundation

struct CaptureDraft: Codable, Equatable, Sendable {
    var text = ""
    var nextAction = ""
    var dueDate = Date()
    var hasExactTime = false
    var effortMinutes: Int?
    var deadlineReminderAt: Date?
}

struct Workspace: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var items: [Item] = []
    var preferences = ReminderPreferences()
    var appearance: Appearance = .system
    var lastMode: ItemKind = .idea
    var drafts: [String: CaptureDraft] = [:]
    var revision = 0
    var randomSeed: UInt64 = UInt64.random(in: 1...UInt64.max)
    var runtime = ScheduleRuntime()
}

@MainActor protocol WorkspaceRepository {
    /// 读取快照；解码或持久化失败时抛出错误，绝不以空库掩盖故障。
    func load() throws -> Workspace
    /// 原子保存快照；失败保留旧库，由调用者保持原界面内容。
    func save(_ workspace: Workspace) throws
}

protocol ReminderPlanner: Sendable {
    /// 纯计算；existing 为实际仍待触发请求，history 仅为过去的已计划时刻。
    func makePlan(workspace: Workspace, now: Date, calendar: Calendar,
                  existing: [ReminderIntent]) -> SchedulePlan
}

@MainActor protocol ReminderDelivery {
    func pending() async -> [ReminderIntent]
    func replaceSchedule(_ intents: [ReminderIntent]) async -> DeliveryReport
}

protocol CapabilityProvider {
    func query() -> Capabilities
}

struct LocalCapabilities: CapabilityProvider {
    func query() -> Capabilities { Capabilities() }
    func requestMode(_ mode: ReminderMode) throws {
        if mode == .cloud { throw DomainError.cloudUnavailable }
    }
}
