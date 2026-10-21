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
    var textFormat: TextFormat = .markdown
    var attachments: [Attachment] = []
}

struct Workspace: Codable, Equatable, Sendable {
    var schemaVersion = 2
    var items: [Item] = []
    var preferences = ReminderPreferences()
    var appearance: Appearance = .system
    var lastMode: ItemKind = .idea
    var drafts: [String: CaptureDraft] = [:]
    var revision = 0
    var randomSeed: UInt64 = UInt64.random(in: 1...UInt64.max)
    var runtime = ScheduleRuntime()
    var notificationOnboarding = NotificationOnboarding()
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

extension CaptureDraft {
    private enum CodingKeys: String, CodingKey {
        case text, nextAction, dueDate, hasExactTime, effortMinutes, deadlineReminderAt, textFormat, attachments
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        nextAction = try c.decode(String.self, forKey: .nextAction)
        dueDate = try c.decode(Date.self, forKey: .dueDate)
        hasExactTime = try c.decode(Bool.self, forKey: .hasExactTime)
        effortMinutes = try c.decodeIfPresent(Int.self, forKey: .effortMinutes)
        deadlineReminderAt = try c.decodeIfPresent(Date.self, forKey: .deadlineReminderAt)
        textFormat = try c.decodeIfPresent(TextFormat.self, forKey: .textFormat) ?? .plain
        attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
    }
}

extension Workspace {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, items, preferences, appearance, lastMode, drafts, revision, randomSeed, runtime, notificationOnboarding
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .schemaVersion)
        guard (1...2).contains(version) else { throw DomainError.invalid("资料版本无法识别，原资料已保留。") }
        schemaVersion = 2
        items = try c.decode([Item].self, forKey: .items)
        preferences = try c.decode(ReminderPreferences.self, forKey: .preferences)
        appearance = try c.decode(Appearance.self, forKey: .appearance)
        lastMode = try c.decode(ItemKind.self, forKey: .lastMode)
        drafts = try c.decode([String: CaptureDraft].self, forKey: .drafts)
        revision = try c.decode(Int.self, forKey: .revision)
        randomSeed = try c.decode(UInt64.self, forKey: .randomSeed)
        runtime = try c.decode(ScheduleRuntime.self, forKey: .runtime)
        notificationOnboarding = try c.decodeIfPresent(NotificationOnboarding.self, forKey: .notificationOnboarding)
            ?? NotificationOnboarding(isNewInstallation: false)
    }
}
