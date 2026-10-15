// 所属层级：L3 外交层（界面）
// 文件职责：统一搜索、已完成、归档与回收站浏览。
// 输入：搜索词与状态过滤；输出：事项导航。
// 依赖：AppModel；不在界面实现删除持久化。
import SwiftUI

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "全部", active = "进行中", completed = "已完成", archived = "已归档", deleted = "回收站"
    var id: String { rawValue }
    func includes(_ item: Item) -> Bool {
        switch self {
        case .all: item.status != .deleted
        case .active: [.active, .paused].contains(item.status)
        case .completed: item.status == .completed
        case .archived: item.status == .archived
        case .deleted: item.status == .deleted
        }
    }
}

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var filter: LibraryFilter = .all

    private var results: [Item] {
        model.workspace.items.filter {
            filter.includes($0) && (query.isEmpty || $0.searchableText.localizedStandardContains(query))
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("查看", selection: $filter) {
                    ForEach(LibraryFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                if results.isEmpty {
                    ContentUnavailableView("这里暂时没有内容", systemImage: "tray", description: Text("换一个范围或关键词试试。"))
                }
                ForEach(results) { item in
                    NavigationLink(value: item.id) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title).lineLimit(3)
                            Text("\(item.kind.label) · \(item.status.label)").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                    }
                }
                if filter == .deleted {
                    Text("删除满 30 天的内容将在下次打开应用时清理。恢复可保留历史，永久删除需要单独确认。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .searchable(text: $query, prompt: "找标题、想法或进度")
            .navigationTitle("之前的念头")
            .navigationDestination(for: UUID.self) { ItemDetailView(id: $0) }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .appFeedback()
        }
    }
}
