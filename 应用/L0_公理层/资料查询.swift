// 所属层级：L0 公理层
// 文件职责：定义搜索与历史的范围不变量和稳定排序。
// 输入：事项和筛选值；输出：可读查询结果。
// 依赖：Foundation；星标不参与随机提醒权重。
import Foundation

enum LibraryScope: Sendable { case search, history, trash
    var title: String { switch self { case .search: "搜索"; case .history: "历史记录"; case .trash: "回收站" } }
}

enum LibraryQuery {
    static func results(_ items: [Item], scope: LibraryScope, query: String = "",
                        kind: ItemKind? = nil, status: ItemStatus? = nil) -> [Item] {
        items.filter { item in
            let allowed: Bool
            switch scope {
            case .search: allowed = item.status != .deleted
            case .history: allowed = [.completed, .archived].contains(item.status)
            case .trash: allowed = item.status == .deleted
            }
            return allowed && (kind == nil || item.kind == kind) && (status == nil || item.status == status) &&
                (query.isEmpty || item.searchableText.localizedStandardContains(query))
        }.sorted { $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt }
    }
    static func starredFirst(_ lhs: Item, _ rhs: Item) -> Bool {
        if lhs.isStarred != rhs.isStarred { return lhs.isStarred }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
