// 所属层级：L2 流程层（记录模块）
// 文件职责：创建/编辑事项、补充想法与原地转为计划。
// 输入：草稿和事项；输出：校验后的值类型。
// 依赖：L0 领域；失败：空文本/超长/截止不合法，无持久化副作用。
import Foundation

enum ItemEditing {
    static func create(draft: CaptureDraft, kind: ItemKind, now: Date,
                       timeZone: TimeZone) throws -> Item {
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        try ContentValidation.text(text)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var item = Item(kind: kind, title: String(lines.first ?? ""),
                        body: lines.dropFirst().joined(separator: "\n"), createdAt: now, updatedAt: now)
        item.entries = [ItemEntry(kind: .creation, text: text, createdAt: now)]
        return try update(item, draft: draft, kind: kind, now: now, timeZone: timeZone, recordChange: false)
    }

    static func update(_ original: Item, draft: CaptureDraft, kind: ItemKind, now: Date,
                       timeZone: TimeZone, recordChange: Bool = true) throws -> Item {
        guard original.status != .deleted else { throw DomainError.missingItem }
        var item = original
        let content = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        try ContentValidation.text(content)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        item.kind = kind
        item.title = String(lines.first ?? "")
        item.body = lines.dropFirst().joined(separator: "\n")
        item.nextAction = draft.nextAction
        item.effortMinutes = draft.effortMinutes
        if kind == .plan {
            let old = original.deadline
            let zone = old?.timeZoneID ?? timeZone.identifier
            item.deadline = Deadline(precision: draft.hasExactTime ? .instant : .dateOnly,
                                     value: draft.dueDate, timeZoneID: zone)
            item.deadlineReminderAt = draft.deadlineReminderAt
            if let reminder = item.deadlineReminderAt,
               (reminder != original.deadlineReminderAt && reminder <= now) || reminder >= item.deadline!.boundary {
                throw DomainError.invalid("期限提醒需要在现在之后、截止之前。")
            }
        } else {
            item.deadline = nil
            item.deadlineReminderAt = nil
        }
        item.updatedAt = now
        if recordChange && item != original {
            let change = original.kind != kind ? "琐事转为计划" : "修改了事项内容或截止时间"
            let previous = ([original.title, original.body].filter { !$0.isEmpty }).joined(separator: "\n")
            item.entries.append(ItemEntry(kind: .change, text: change, createdAt: now, previousText: previous))
        }
        try ContentValidation.item(item)
        return item
    }

    static func appendThought(to item: Item, text: String, now: Date) throws -> Item {
        try ContentValidation.text(text)
        guard item.status != .deleted else { throw DomainError.missingItem }
        var item = item
        item.entries.append(ItemEntry(kind: .thought, text: text, createdAt: now))
        item.updatedAt = now
        return item
    }

    static func draft(for item: Item) -> CaptureDraft {
        CaptureDraft(text: ([item.title, item.body].filter { !$0.isEmpty }).joined(separator: "\n"),
                     nextAction: item.nextAction, dueDate: item.deadline?.value ?? Date(),
                     hasExactTime: item.deadline?.precision == .instant,
                     effortMinutes: item.effortMinutes, deadlineReminderAt: item.deadlineReminderAt)
    }
}
