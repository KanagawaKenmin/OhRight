// 所属层级：L3 外交层（界面）
// 文件职责：首页模式、卡片导航和唯一主要记录入口。
// 输入：应用状态；输出：导航与用户命令。
// 依赖：SwiftUI、共用卡片；不直接读写数据库。
import SwiftUI

enum HomeSheet: String, Identifiable {
    case capture, settings, library, freeTime
    var id: String { rawValue }
}

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var sheet: HomeSheet?
    @State private var ideaPosition: UUID?
    @State private var planPosition: UUID?
    @State private var captureKind: ItemKind = .idea

    private var items: [Item] {
        let items = model.workspace.items.filter {
            $0.kind == model.mode && [.active, .paused].contains($0.status)
        }
        return model.mode == .idea ? items.sorted { $0.updatedAt > $1.updatedAt } :
            items.sorted { ($0.deadline?.boundary ?? .distantFuture) < ($1.deadline?.boundary ?? .distantFuture) }
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.path) {
            ZStack {
                ModeBackground(mode: model.mode)
                VStack(spacing: 0) {
                    Picker("内容模式", selection: Binding(get: { model.mode }, set: { model.selectMode($0) })) {
                        ForEach(ItemKind.allCases) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.vertical, 12)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            Text(model.mode == .idea ? "留住一个，还没想完的念头。" : "先往前走一小步。")
                                .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 12)
                            if items.isEmpty {
                                ContentUnavailableView(model.mode == .idea ? "还没有留下念头" : "还没有计划",
                                    systemImage: model.mode == .idea ? "sparkles" : "square.stack",
                                    description: Text(model.mode == .idea ? "先记下一句，没想完整也可以。" : "有了期限，再把它放到这里。"))
                            } else if model.mode == .idea {
                                cards(items)
                            } else {
                                ForEach(PlanSection.allCases) { section in
                                    let group = items.filter { PlanSection.of($0) == section }
                                    if !group.isEmpty {
                                        Text(section.rawValue).font(.caption.weight(.bold)).padding(.top, 12)
                                        cards(group)
                                    }
                                }
                            }
                        }.padding(.horizontal, 20).padding(.bottom, 20).scrollTargetLayout()
                    }.scrollPosition(id: model.mode == .idea ? $ideaPosition : $planPosition)
                }
            }
            .navigationTitle("哦对了")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("搜索、完成与归档", systemImage: "magnifyingglass") { sheet = .library }
                        Button("提醒与设置", systemImage: "slider.horizontal.3") { sheet = .settings }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                        .accessibilityLabel("更多")
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if model.mode == .idea {
                        Button("我现在有空") { sheet = .freeTime }.frame(minHeight: 44)
                    }
                    Button { captureKind = model.mode; sheet = .capture } label: {
                        Label(model.mode == .idea ? "记一下" : "新计划", systemImage: "plus")
                            .font(.headline).frame(maxWidth: .infinity).frame(minHeight: 54)
                    }
                    .foregroundStyle(Color("OnAccent")).background(AppPalette.accent(model.mode),
                        in: RoundedRectangle(cornerRadius: model.mode == .idea ? 28 : 8))
                    .accessibilityIdentifier("capturePrimary")
                }.padding(.horizontal, 24).padding(.bottom, 12).background(.bar)
            }
            .navigationDestination(for: UUID.self) { ItemDetailView(id: $0) }
            .sheet(item: $sheet) { route in
                switch route {
                case .capture: ItemEditorView(kind: captureKind)
                case .settings: SettingsView()
                case .library: LibraryView()
                case .freeTime: FreeTimeView()
                }
            }
            .onChange(of: model.path) { _, value in if !value.isEmpty { sheet = nil } }
            .onChange(of: model.routeGeneration) { _, _ in sheet = nil }
            .appFeedback()
        }.tint(AppPalette.accent(model.mode))
    }

    private func cards(_ items: [Item]) -> some View {
        ForEach(items) { item in
            NavigationLink(value: item.id) { ItemCard(item: item) }.buttonStyle(.plain).id(item.id)
                .accessibilityIdentifier("itemCard/\(item.kind.rawValue)/\(item.id.uuidString)")
        }
    }
}
