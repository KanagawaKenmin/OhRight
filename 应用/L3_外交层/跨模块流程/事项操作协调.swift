// 所属层级：L3 外交层
// 文件职责：调用记录/计划用例并保存，协调通知重建。
// 输入：用户动作；输出：资料变化与后续重排。
// 依赖：L2 记录、计划；不复制模块内校验。
import Foundation

extension AppModel {
    func saveItem(draft: CaptureDraft, kind: ItemKind, existingID: UUID?, draftKey: String) throws {
        let now = Date()
        var next = workspace
        if let id = existingID {
            guard let index = next.items.firstIndex(where: { $0.id == id }) else { throw DomainError.missingItem }
            next.items[index] = try ItemEditing.update(next.items[index], draft: draft, kind: kind,
                                                       now: now, timeZone: calendar.timeZone)
        } else {
            let item = try ItemEditing.create(draft: draft, kind: kind, now: now, timeZone: calendar.timeZone)
            next.items.insert(item, at: 0)
        }
        next.drafts.removeValue(forKey: draftKey)
        if let item = existingID.flatMap({ id in next.items.first { $0.id == id } }) ?? next.items.first,
           let reminder = item.deadlineReminderAt, reminder > now,
           !next.preferences.allows(reminder, calendar: calendar) {
            throw DomainError.invalid("提醒时间在免打扰内，请选择更早的允许时间。")
        }
        try commit(next)
    }

    func transformItem(_ id: UUID, using operation: (Item) throws -> Item) throws {
        var next = workspace
        guard let index = next.items.firstIndex(where: { $0.id == id }) else { throw DomainError.missingItem }
        next.items[index] = try operation(next.items[index])
        try ContentValidation.item(next.items[index])
        try commit(next)
    }

    func lifecycle(_ id: UUID, action: LifecycleAction) throws {
        try transformItem(id) { try ItemLifecycle.apply(action, to: $0, now: Date()) }
        if case .complete = action { notice = "这件事，做到了。" }
    }

    func append(_ id: UUID, text: String) throws {
        try transformItem(id) {
            if $0.kind == .idea { return try ItemEditing.appendThought(to: $0, text: text, now: Date()) }
            return try PlanProgress.append(to: $0, text: text, now: Date())
        }
    }

    func mute(_ id: UUID, permanently: Bool) throws {
        try transformItem(id) { original in
            var item = original
            if permanently { item.reminderEnabled.toggle() }
            else { item.mutedUntil = calendar.date(byAdding: .day, value: 7, to: Date()) }
            return item
        }
    }

    func unmute(_ id: UUID) throws {
        try transformItem(id) { original in
            var item = original
            item.mutedUntil = nil
            item.reminderEnabled = true
            return item
        }
    }

    func permanentlyDelete(_ id: UUID) throws {
        guard item(id)?.status == .deleted else { throw DomainError.invalid("请先移入回收站。") }
        var next = workspace
        next.items.removeAll { $0.id == id }
        try commit(next)
    }
}
