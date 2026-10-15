// 所属层级：L0 公理层
// 文件职责：定义事项、时间线与检查项的值类型。
// 主要输入：用户内容；主要输出：可编码的领域快照。
// 依赖：Foundation；对外接口：Item、ItemEntry、ChecklistStep。
// 禁止事项：不访问持久化、系统通知或界面。
import Foundation

enum ItemKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case idea, plan
    var id: String { rawValue }
    var label: String { self == .idea ? "琐事" : "计划" }
}

enum ItemStatus: String, Codable, CaseIterable, Sendable {
    case active, paused, completed, archived, deleted
    var label: String {
        switch self {
        case .active: "进行中"
        case .paused: "已暂停"
        case .completed: "已完成"
        case .archived: "已归档"
        case .deleted: "回收站"
        }
    }
}

enum EntryKind: String, Codable, Sendable { case creation, thought, progress, change }

struct ItemEntry: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var kind: EntryKind
    var text: String
    var createdAt: Date
    var previousText: String?
    var editedAt: Date?
}

struct ChecklistStep: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var text: String
    var isDone = false
    var completedAt: Date?
}

struct Item: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var kind: ItemKind
    var title: String
    var body: String
    var status: ItemStatus = .active
    var createdAt: Date
    var updatedAt: Date
    var nextAction = ""
    var effortMinutes: Int?
    var deadline: Deadline?
    var deadlineReminderAt: Date?
    var reminderEnabled = true
    var mutedUntil: Date?
    var completedAt: Date?
    var deletedAt: Date?
    var resumeStatus: ItemStatus = .active
    var beforeDeleteStatus: ItemStatus = .active
    var entries: [ItemEntry] = []
    var steps: [ChecklistStep] = []

    var lastProgressAt: Date {
        let progress = entries.filter { $0.kind == .progress }.map(\.createdAt)
        return (progress + steps.compactMap(\.completedAt)).max() ?? createdAt
    }
    var isRemindable: Bool { status == .active && reminderEnabled }
    var completedStepCount: Int { steps.filter(\.isDone).count }
    var searchableText: String {
        ([title, body, nextAction] + entries.map(\.text) + steps.map(\.text)).joined(separator: "\n")
    }
}
