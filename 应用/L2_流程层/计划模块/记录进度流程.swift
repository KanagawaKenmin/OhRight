// 所属层级：L2 流程层（计划模块）
// 文件职责：记录真实进展、维护下一步与平铺检查项。
// 输入：事项、用户内容；输出：更新的事项。
// 依赖：L0；不自动把步骤全勾选解释为整项完成。
import Foundation

enum PlanProgress {
    static func append(to original: Item, text: String, now: Date, format: TextFormat = .plain,
                       attachments: [Attachment] = []) throws -> Item {
        try ContentValidation.text(text)
        guard original.kind == .plan, original.status != .deleted else { throw DomainError.missingItem }
        var item = original
        item.entries.append(ItemEntry(kind: .progress, text: text, createdAt: now, textFormat: format, attachments: attachments))
        item.updatedAt = now
        return item
    }

    static func addStep(to original: Item, text: String, now: Date) throws -> Item {
        try ContentValidation.text(text, limit: 500)
        var item = original
        guard item.kind == .plan, item.status != .deleted else { throw DomainError.missingItem }
        item.steps.append(ChecklistStep(text: text))
        item.updatedAt = now
        return item
    }

    static func toggleStep(in original: Item, stepID: UUID, now: Date) throws -> Item {
        var item = original
        guard item.status != .deleted, let index = item.steps.firstIndex(where: { $0.id == stepID }) else {
            throw DomainError.missingItem
        }
        item.steps[index].isDone.toggle()
        item.steps[index].completedAt = item.steps[index].isDone ? now : nil
        item.updatedAt = now
        return item
    }

    static func editEntry(in original: Item, entryID: UUID, text: String, now: Date,
                          format: TextFormat? = nil, attachments: [Attachment]? = nil) throws -> Item {
        try ContentValidation.text(text)
        var item = original
        guard item.status != .deleted, let index = item.entries.firstIndex(where: { $0.id == entryID }),
              [.thought, .progress, .creation].contains(item.entries[index].kind) else {
            throw DomainError.invalid("这条记录不能编辑。")
        }
        item.entries[index].previousText = item.entries[index].text
        item.entries[index].previousFormat = item.entries[index].textFormat
        item.entries[index].previousAttachments = item.entries[index].attachments
        item.entries[index].text = text
        if let format { item.entries[index].textFormat = format }
        if let attachments { item.entries[index].attachments = attachments }
        item.entries[index].editedAt = now
        item.updatedAt = now
        return item
    }
}
