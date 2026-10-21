// 所属层级：L3 外交层
// 文件职责：星标、可撤销归档/删除；撤销前核对事项没有后续修改。
// 输入：事项动作；输出：原子保存与一次撤销机会。
// 依赖：L2 生命周期、AppModel；不覆写后续编辑。
import Foundation

struct ItemUndo {
    let before: Item
    let after: Item
}

extension AppModel {
    func toggleStar(_ id: UUID) throws {
        try transformItem(id) { value in
            var next = value
            next.isStarred.toggle()
            return next
        }
    }

    func quickAction(_ id: UUID, action: LifecycleAction) throws {
        guard let before = item(id) else { throw DomainError.missingItem }
        try lifecycle(id, action: action)
        if let after = item(id) { undoItem = ItemUndo(before: before, after: after) }
        notice = action == .archive ? "已归档" : "已移入回收站"
    }

    func undoQuickAction() {
        guard let undo = undoItem else { return }
        attempt {
            guard item(undo.after.id) == undo.after else {
                throw DomainError.invalid("这条内容已有后续修改，请在历史记录或回收站恢复。")
            }
            try transformItem(undo.after.id) { _ in undo.before }
            undoItem = nil
            notice = "已撤销"
        }
    }
}
