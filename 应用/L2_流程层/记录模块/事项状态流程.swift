// 所属层级：L2 流程层（记录模块）
// 文件职责：完成、暂停、归档、删除与恢复状态转换。
// 输入：事项、动作、时钟；输出：变更后事项。
// 依赖：L0；失败：非法动作；重复目标状态不重复写历史。
import Foundation

enum LifecycleAction: Sendable, Equatable { case complete, reopen, pause, resume, archive, delete, restore }

enum ItemLifecycle {
    static func apply(_ action: LifecycleAction, to original: Item, now: Date) throws -> Item {
        var item = original
        let target: ItemStatus
        switch action {
        case .complete:
            guard item.status != .deleted else { throw DomainError.missingItem }
            if item.status == .completed { return item }
            item.resumeStatus = item.status
            item.completedAt = now
            target = .completed
        case .reopen:
            guard [.completed, .archived].contains(item.status) else { return item }
            target = item.resumeStatus == .paused && item.kind == .plan ? .paused : .active
            item.completedAt = nil
        case .pause:
            guard item.kind == .plan, item.status == .active else {
                throw DomainError.invalid("只有进行中的计划可以暂停。")
            }
            target = .paused
        case .resume:
            guard item.status == .paused else { return item }
            target = .active
        case .archive:
            guard item.status != .deleted else { throw DomainError.missingItem }
            if item.status == .archived { return item }
            item.resumeStatus = item.status
            target = .archived
        case .delete:
            if item.status == .deleted { return item }
            item.beforeDeleteStatus = item.status
            item.deletedAt = now
            target = .deleted
        case .restore:
            guard item.status == .deleted else { return item }
            target = item.beforeDeleteStatus == .deleted ? .active : item.beforeDeleteStatus
            item.deletedAt = nil
        }
        item.status = target
        item.updatedAt = now
        item.entries.append(ItemEntry(kind: .change, text: "状态：\(target.label)", createdAt: now))
        return item
    }
}
