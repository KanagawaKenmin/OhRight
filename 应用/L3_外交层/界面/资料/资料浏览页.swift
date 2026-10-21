// 所属层级：L3 外交层（界面）
// 文件职责：独立搜索、历史、回收站路由，共用查询展示。
// 输入：明确浏览范围、关键词、类别；输出：事项导航。
// 依赖：AppModel、LibraryQuery；历史不会混入进行中事项。
import SwiftUI

struct LibraryView: View {
    var scope: LibraryScope = .search
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            LibraryContent(scope: scope)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

struct LibraryContent: View {
    let scope: LibraryScope
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var status: ItemStatus?
    @State private var kind: ItemKind?
    private var results: [Item] {
        LibraryQuery.results(model.workspace.items, scope: scope, query: query, kind: kind, status: status)
    }
    var body: some View {
        List {
            if scope != .trash {
                Picker("状态", selection: $status) {
                    Text("全部").tag(nil as ItemStatus?)
                    ForEach(scope == .history ? [ItemStatus.completed, .archived] : [.active, .paused, .completed, .archived], id: \.self) {
                        Text($0.label).tag(Optional($0))
                    }
                }
                if scope == .search {
                    Picker("类别", selection: $kind) {
                        Text("全部").tag(nil as ItemKind?)
                        ForEach(ItemKind.allCases) { Text($0.label).tag(Optional($0)) }
                    }
                }
            }
            if results.isEmpty { ContentUnavailableView("这里暂时没有内容", systemImage: "tray") }
            ForEach(results) { item in
                NavigationLink(value: item.id) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title).lineLimit(3)
                        Text("\(item.kind.label) · \(item.status.label)").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
            }
            if scope == .trash {
                Text("删除满 30 天的内容将在下次打开应用时清理。恢复可保留历史，永久删除需要单独确认。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .searchable(text: $query, prompt: "搜索内容")
        .navigationTitle(scope.title)
        .navigationDestination(for: UUID.self) { ItemDetailView(id: $0) }
        .appFeedback()
    }
}
