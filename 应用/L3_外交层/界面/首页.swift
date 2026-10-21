// 所属层级：L3 外交层（界面）
// 文件职责：首页模式、卡片导航和唯一主要记录入口。
// 输入：应用状态；输出：导航与用户命令。
// 依赖：SwiftUI、共用卡片；不直接读写数据库。
import SwiftUI

enum HomeSheet: String, Identifiable {
    case capture, settings, library, history, freeTime
    var id: String { rawValue }
}

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var sheet: HomeSheet?
    @State private var ideaPosition: UUID?
    @State private var planPosition: UUID?
    @State private var captureKind: ItemKind = .idea
    @State private var selectedItem: UUID?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.path) {
            ZStack {
                ModeBackground(mode: model.mode)
                VStack(spacing: 0) {
                    Picker("内容模式", selection: Binding(get: { model.mode }, set: { model.selectMode($0) })) {
                        ForEach(ItemKind.allCases) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.vertical, 12)
                    notificationStatus
                    ZStack {
                        homeList(mode: .idea, position: $ideaPosition)
                            .opacity(model.mode == .idea ? 1 : 0).allowsHitTesting(model.mode == .idea)
                            .accessibilityHidden(model.mode != .idea)
                        homeList(mode: .plan, position: $planPosition)
                            .opacity(model.mode == .plan ? 1 : 0).allowsHitTesting(model.mode == .plan)
                            .accessibilityHidden(model.mode != .plan)
                    }
                }
            }
            .navigationTitle("哦对了")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("搜索", systemImage: "magnifyingglass") { sheet = .library }
                        Button("历史记录", systemImage: "clock") { sheet = .history }
                        Button("设置", systemImage: "gearshape") { sheet = .settings }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                        .accessibilityLabel("更多")
                }
            }
            .safeAreaInset(edge: .bottom) { primaryActions }
            .navigationDestination(for: UUID.self) { ItemDetailView(id: $0) }
            .sheet(item: $sheet) { route in
                switch route {
                case .capture: ItemEditorView(kind: captureKind)
                case .settings: SettingsView()
                case .library: LibraryView()
                case .history: LibraryView(scope: .history)
                case .freeTime: FreeTimeView()
                }
            }
            .task { await model.prepareNotificationOnboarding() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && sheet == nil && model.path.isEmpty { Task { await model.prepareNotificationOnboarding() } }
            }
            .onChange(of: sheet) { _, value in
                if value == nil { Task { await model.prepareNotificationOnboarding() } }
            }
            .onChange(of: model.mode) { _, _ in selectedItem = nil }
            .onChange(of: model.path) { _, value in if !value.isEmpty { sheet = nil } }
            .onChange(of: model.routeGeneration) { _, _ in sheet = nil }
            .appFeedback()
        }.tint(AppPalette.accent(model.mode))
    }

    private func homeList(mode: ItemKind, position: Binding<UUID?>) -> some View {
        let items = model.workspace.items.filter { $0.kind == mode && [.active, .paused].contains($0.status) }
        return ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            Text(mode == .idea ? "留住一个，还没想完的念头。" : "先往前走一小步。")
                                .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 12)
                            if items.isEmpty {
                                ContentUnavailableView(mode == .idea ? "还没有留下念头" : "还没有计划",
                                    systemImage: mode == .idea ? "sparkles" : "square.stack",
                                    description: Text(mode == .idea ? "先记下一句，没想完整也可以。" : "有了期限，再把它放到这里。"))
                            } else if mode == .idea {
                                cards(items.sorted(by: LibraryQuery.starredFirst))
                            } else {
                                ForEach(PlanSection.allCases) { section in
                                    let group = items.filter { PlanSection.of($0) == section }
                                    if !group.isEmpty {
                                        Text(section.rawValue).font(.caption.weight(.bold)).padding(.top, 12)
                                        cards(group.sorted { lhs, rhs in
                                            if lhs.isStarred != rhs.isStarred { return lhs.isStarred }
                                            return (lhs.deadline?.boundary ?? .distantFuture) < (rhs.deadline?.boundary ?? .distantFuture)
                                        })
                                    }
                                }
                            }
                            HomeBlankArea(selected: $selectedItem, height: items.isEmpty ? 220 : 120)
                        }.padding(.horizontal, 20).padding(.bottom, 20).scrollTargetLayout()
        }.scrollPosition(id: position)
    }

    private var primaryActions: some View {
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

    @ViewBuilder private var notificationStatus: some View {
        if model.notificationAccess == .denied {
            HStack { Text("通知未开启"); Spacer(); Button("前往设置") { openNotificationSettings() } }.padding(.horizontal, 20)
        } else if model.workspace.notificationOnboarding.offerEnable {
            HStack {
                Text("通知已允许，提醒已暂停")
                Spacer()
                Button("开启提醒") { var value = model.preferences; value.enabled = true; model.attempt { try model.savePreferences(value) } }
                Button("关闭") {
                    model.attempt { var next = model.workspace; next.notificationOnboarding.offerEnable = false; try model.commit(next) }
                }.accessibilityLabel("关闭开启提醒提示")
            }.font(.subheadline).padding(.horizontal, 20)
        }
    }

    private func cards(_ items: [Item]) -> some View {
        ForEach(items) { item in
            VStack(spacing: 0) {
                HomeActionCard(item: item, selected: $selectedItem)
                HomeBlankArea(selected: $selectedItem, height: 16)
            }.id(item.id)
        }
    }
}
