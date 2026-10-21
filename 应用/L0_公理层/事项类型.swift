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
    var textFormat: TextFormat = .plain
    var previousFormat: TextFormat?
    var attachments: [Attachment] = []
    var previousAttachments: [Attachment] = []
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
    var isStarred = false
    var textFormat: TextFormat = .plain
    var attachments: [Attachment] = []

    var lastProgressAt: Date {
        let progress = entries.filter { $0.kind == .progress }.map(\.createdAt)
        return (progress + steps.compactMap(\.completedAt)).max() ?? createdAt
    }
    var isRemindable: Bool { status == .active && reminderEnabled }
    var completedStepCount: Int { steps.filter(\.isDone).count }
    var searchableText: String {
        ([title, ReadableText.plain(body, format: textFormat), nextAction] +
         entries.map { ReadableText.plain($0.text, format: $0.textFormat) } + steps.map(\.text)).joined(separator: "\n")
    }
}

extension Item {
    private enum CodingKeys: String, CodingKey {
        case id, kind, title, body, status, createdAt, updatedAt, nextAction, effortMinutes, deadline
        case deadlineReminderAt, reminderEnabled, mutedUntil, completedAt, deletedAt, resumeStatus, beforeDeleteStatus
        case entries, steps, isStarred, textFormat, attachments
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(ItemKind.self, forKey: .kind)
        title = try c.decode(String.self, forKey: .title)
        body = try c.decode(String.self, forKey: .body)
        status = try c.decode(ItemStatus.self, forKey: .status)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        nextAction = try c.decode(String.self, forKey: .nextAction)
        effortMinutes = try c.decodeIfPresent(Int.self, forKey: .effortMinutes)
        deadline = try c.decodeIfPresent(Deadline.self, forKey: .deadline)
        deadlineReminderAt = try c.decodeIfPresent(Date.self, forKey: .deadlineReminderAt)
        reminderEnabled = try c.decode(Bool.self, forKey: .reminderEnabled)
        mutedUntil = try c.decodeIfPresent(Date.self, forKey: .mutedUntil)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        resumeStatus = try c.decode(ItemStatus.self, forKey: .resumeStatus)
        beforeDeleteStatus = try c.decode(ItemStatus.self, forKey: .beforeDeleteStatus)
        entries = try c.decode([ItemEntry].self, forKey: .entries)
        steps = try c.decode([ChecklistStep].self, forKey: .steps)
        isStarred = try c.decodeIfPresent(Bool.self, forKey: .isStarred) ?? false
        textFormat = try c.decodeIfPresent(TextFormat.self, forKey: .textFormat) ?? .plain
        attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
    }
}

extension ItemEntry {
    private enum CodingKeys: String, CodingKey {
        case id, kind, text, createdAt, previousText, editedAt, textFormat, previousFormat, attachments, previousAttachments
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(EntryKind.self, forKey: .kind)
        text = try c.decode(String.self, forKey: .text)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        previousText = try c.decodeIfPresent(String.self, forKey: .previousText)
        editedAt = try c.decodeIfPresent(Date.self, forKey: .editedAt)
        textFormat = try c.decodeIfPresent(TextFormat.self, forKey: .textFormat) ?? .plain
        previousFormat = try c.decodeIfPresent(TextFormat.self, forKey: .previousFormat)
        attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        previousAttachments = try c.decodeIfPresent([Attachment].self, forKey: .previousAttachments) ?? []
    }
}

