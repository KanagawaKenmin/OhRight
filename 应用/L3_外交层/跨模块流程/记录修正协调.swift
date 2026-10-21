// 所属层级：L3 外交层
// 文件职责：将记录修正与含图编辑草稿清除放进同一事务。
// 输入：草稿和稳定记录编号；输出：历史与已保存记录。
// 依赖：PlanProgress、AppModel；失败保留草稿和旧资料。
import Foundation

extension AppModel {
    func saveEntryEdit(_ id: UUID, entryID: UUID, draft: CaptureDraft, draftKey: String) throws {
        var next = workspace
        guard let index = next.items.firstIndex(where: { $0.id == id }) else { throw DomainError.missingItem }
        next.items[index] = try PlanProgress.editEntry(in: next.items[index], entryID: entryID, text: draft.text,
            now: Date(), format: draft.textFormat, attachments: draft.attachments)
        try ContentValidation.item(next.items[index])
        next.drafts.removeValue(forKey: draftKey)
        try commit(next)
    }
}
