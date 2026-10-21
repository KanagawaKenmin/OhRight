// 所属层级：L0 公理层
// 文件职责：定义用户内容和偏好的有效边界。
// 输入：事项/提醒偏好；输出：成功或可读错误。
// 依赖：领域类型；禁止静默截断内容或修复损坏备份。
import Foundation

enum ContentValidation {
    static func text(_ text: String, limit: Int = 20_000) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainError.invalid("先写下一句话吧。")
        }
        guard text.count <= limit else { throw DomainError.invalid("内容过长，请控制在 \(limit) 个字符内。") }
    }

    static func item(_ item: Item) throws {
        try text(item.title, limit: 120)
        guard item.body.count <= 20_000, item.nextAction.count <= 20_000 else {
            throw DomainError.invalid("正文或下一步超过 20,000 个字符。")
        }
        guard item.kind != .plan || item.deadline != nil else {
            throw DomainError.invalid("计划需要一个截止日期。")
        }
        guard item.kind == .plan || (item.deadline == nil && item.status != .paused) else {
            throw DomainError.invalid("琐事不能带有计划截止或暂停状态。")
        }
        if let deadline = item.deadline {
            guard TimeZone(identifier: deadline.timeZoneID) != nil else {
                throw DomainError.invalid("截止日期包含无法识别的时区。")
            }
            try date(deadline.value)
            if let reminder = item.deadlineReminderAt, reminder >= deadline.boundary {
                throw DomainError.invalid("期限提醒必须在截止之前。")
            }
        }
        for value in [item.createdAt, item.updatedAt] + [item.deadlineReminderAt, item.mutedUntil,
            item.completedAt, item.deletedAt].compactMap({ $0 }) { try date(value) }
        for entry in item.entries {
            try text(entry.text)
            if let previous = entry.previousText, previous.count > 20_000 { throw DomainError.invalid("历史记录文字过长。") }
            try attachmentGroup(entry.attachments)
            try attachmentGroup(entry.previousAttachments)
            try date(entry.createdAt)
            if let edited = entry.editedAt { try date(edited) }
        }
        guard item.attachments.count + item.entries.flatMap(\.attachments).count <= Attachment.maximumPerItem else {
            throw DomainError.invalid("每条事项及记录最多保留 20 张图片。")
        }
        try attachmentGroup(item.attachments)
        for step in item.steps { try text(step.text, limit: 500) }
        if let effort = item.effortMinutes, !(1...1440).contains(effort) {
            throw DomainError.invalid("预计时长须在 1–1440 分钟之间。")
        }
    }

    static func attachmentGroup(_ attachments: [Attachment]) throws {
        guard attachments.count <= Attachment.maximumPerItem,
              Set(attachments.map(\.id)).count == attachments.count else { throw DomainError.invalid("图片数量过多或编号重复。") }
        for attachment in attachments { try attachment.validate() }
    }

    static func date(_ value: Date) throws {
        guard value.timeIntervalSince1970.isFinite, (-62_135_596_800...253_402_300_799).contains(value.timeIntervalSince1970) else {
            throw DomainError.invalid("日期超出可识别范围。")
        }
    }

    static func preferences(_ preferences: ReminderPreferences) throws {
        guard preferences.mode == .local else { throw DomainError.cloudUnavailable }
        guard (0...2).contains(preferences.ideaDailyLimit), (0..<1440).contains(preferences.digestMinute),
              preferences.quietIntervals.allSatisfy({
                  (0..<1440).contains($0.startMinute) && (0..<1440).contains($0.endMinute)
              }) else { throw DomainError.invalid("提醒时间或次数无效。") }
        if preferences.digestEnabled && preferences.timePolicy == .avoidQuiet {
            guard !preferences.quietIntervals.contains(where: { $0.contains(minute: preferences.digestMinute) }) else {
                throw DomainError.invalid("回顾时间在免打扰时段内，请调整时间。")
            }
        }
    }
}
