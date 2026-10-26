// 所属层级：L2 流程层（提醒模块）
// 文件职责：校验用户稍后操作并生成独立提醒。
// 输入：原通知、快照、时钟；输出：新意图或明确错误。
// 依赖：L0、L1 时间抽样；不访问系统通知。
import Foundation

enum SnoozeReminder {
    static func make(from source: ReminderIntent, workspace: Workspace, now: Date,
                     calendar: Calendar) throws -> ReminderIntent {
        guard workspace.preferences.enabled,
              let itemID = source.itemIDs.first,
              let item = workspace.items.first(where: { $0.id == itemID }), item.isRemindable else {
            throw DomainError.invalid("内容已完成、暂停或关闭提醒，不再安排稍后提醒。")
        }
        let count = workspace.runtime.snoozeActions.filter { calendar.isDate($0, inSameDayAs: now) }.count
        guard count < 2 else { throw DomainError.invalid("今天已经稍后提醒两次，可以在应用里调整安排。") }
        let pending = Dictionary((workspace.runtime.intents + workspace.runtime.requestedSnoozes)
            .filter { $0.category == .snooze && $0.fireAt > now }.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last }).values
        guard pending.count < 4 || pending.contains(where: { $0.itemIDs == [itemID] }) else {
            throw DomainError.invalid("稍后提醒较多，请先处理已有内容。")
        }
        guard let time = TimeSampling.nextAllowed(after: now.addingTimeInterval(3600),
                                                  calendar: calendar, preferences: workspace.preferences) else {
            throw DomainError.invalid("当前没有允许提醒的时间，请调整免打扰。")
        }
        return ReminderIntent(id: "local/snooze/\(itemID)", category: .snooze, itemIDs: [itemID], fireAt: time,
                              title: "哦对了，稍后再看看", body: workspace.preferences.contentPreview ? item.title : "打开看看这条内容。",
                              sound: false)
    }
}
