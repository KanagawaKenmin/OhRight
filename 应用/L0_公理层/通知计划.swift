// 所属层级：L0 公理层
// 文件职责：定义稳定通知意图及排程结果。
// 主要输入：事项快照；输出：不依赖通知框架的值。
// 依赖：Foundation；对外接口：ReminderIntent、SchedulePlan。
// 禁止事项：不把提交成功当作已经送达。
import Foundation

enum ReminderCategory: String, Codable, Sendable { case idea, digest, deadline, snooze }

struct ReminderIntent: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var category: ReminderCategory
    var itemIDs: [UUID]
    var fireAt: Date
    var title: String
    var body: String
    var sound: Bool

    var fingerprint: String {
        let payload = "\(id)|\(fireAt.timeIntervalSince1970)|\(title)|\(body)|\(sound)|\(itemIDs)"
        return String(StableHash.value(payload), radix: 16)
    }
}

enum StableHash {
    static func value(_ text: String) -> UInt64 {
        text.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
    }
}

struct SchedulePlan: Sendable {
    var intents: [ReminderIntent]
    var coverageEnd: Date
    var omittedDeadlines: Int
    var capacityLimited = false
}

struct DeliveryReport: Sendable {
    var accepted: [ReminderIntent]
    var errors: [String]
}

struct ScheduleRuntime: Codable, Equatable, Sendable {
    var intents: [ReminderIntent] = []
    var history: [ReminderIntent] = []
    var coverageEnd: Date?
    var appliedRevision: Int = -1
    var omittedDeadlines = 0
    var capacityLimited = false
    var lastError: String?
    var timeZoneID = ""
    var lastPreferences: ReminderPreferences?
    var handledActions: [String: Date] = [:]
    var snoozeActions: [Date] = []
    var requestedSnoozes: [ReminderIntent] = []
    var resetQueue = false
}
