// 所属层级：L3 外交层（界面）
// 文件职责：首页模式、整页手势、卡片导航和唯一记录入口。
// 输入：应用与交互状态；输出：导航、模式提交与用户命令。
// 依赖：模式列表、UIKit 手势桥接；不直接读写数据库。
import SwiftUI

enum HomeSheet: String, Identifiable {
    case capture, settings, library, history, freeTime
    var id: String { rawValue }
}

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheet: HomeSheet?
    @State private var captureKind: ItemKind = .idea
    @State private var interaction = HomeInteraction()
    @State private var regions: [HomeHitRegion: CGRect] = [:]
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 30.0
    private var acceptsGesture: Bool { sheet == nil && model.path.isEmpty && scenePhase == .active }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.path) { observedContent }
            .tint(AppPalette.accent(model.mode))
    }

    // 各段提供独立的 opaque 返回类型，避免导航、手势和生命周期合为一个求解表达式。
    private var routedContent: some View {
        gestureContent
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { ItemDetailView(id: $0).toolbar(.visible, for: .navigationBar) }
            .sheet(item: $sheet, content: sheetContent)
    }

    private var observedContent: some View {
        routedContent
            .task { await model.prepareNotificationOnboarding() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { interaction.reset() }
                if phase == .active && sheet == nil && model.path.isEmpty { Task { await model.prepareNotificationOnboarding() } }
            }
            .onChange(of: sheet) { _, value in
                interaction.reset()
                if value == nil { Task { await model.prepareNotificationOnboarding() } }
            }
            .onChange(of: model.mode) { _, _ in interaction.reset() }
            .onChange(of: model.path) { _, value in interaction.reset(); if !value.isEmpty { sheet = nil } }
            .onChange(of: model.routeGeneration) { _, _ in sheet = nil; interaction.reset() }
            .appFeedback()
    }

    private var gestureContent: some View {
        GeometryReader { geometry in
            canvas(width: geometry.size.width)
                // 标题旁 Spacer、列表间隙等透明内容也属于整页滑动区域。
                .contentShape(.interaction, Rectangle())
                .coordinateSpace(name: "homeGestures")
                .onPreferenceChange(HomeHitRegions.self) { regions = $0 }
                .gesture(panGesture(width: geometry.size.width))
                // UIKit 桥接只支持 gesture 重载，不能传入要求 SwiftUI.Gesture 的 simultaneousGesture。
                .gesture(backgroundTap)
        }
    }

    private func canvas(width: CGFloat) -> some View {
        ZStack {
            ModeBackground(mode: model.mode)
            VStack(spacing: 0) {
                header
                notificationStatus
                ZStack { page(.idea, width: width); page(.plan, width: width) }.clipped()
                primaryActions
            }
        }
    }

    private func panGesture(width: CGFloat) -> HomePanGesture {
        HomePanGesture(regions: regions, enabled: acceptsGesture) { event in handle(event, width: width) }
    }

    private var backgroundTap: HomeBackgroundTap {
        // 只有展开卡片时才需要空白点击收起，普通页面拖动不引入第二个候选识别器。
        HomeBackgroundTap(regions: regions, enabled: acceptsGesture && interaction.openedItemID != nil) {
            withAnimation(AppPalette.motion(reduced: reduceMotion)) { interaction.reset() }
        }
    }

    @ViewBuilder private func sheetContent(_ route: HomeSheet) -> some View {
        switch route {
        case .capture: ItemEditorView(kind: captureKind)
        case .settings: SettingsView()
        case .library: LibraryView()
        case .history: LibraryView(scope: .history)
        case .freeTime: FreeTimeView()
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                Text("哦对了").font(.system(size: titleSize, weight: .bold))
                    .accessibilityAddTraits(.isHeader).accessibilityIdentifier("homeTitle")
                Spacer()
                Menu {
                    Button("搜索", systemImage: "magnifyingglass") { sheet = .library }
                    Button("历史记录", systemImage: "clock") { sheet = .history }
                    Button("设置", systemImage: "gearshape") { sheet = .settings }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).background(.thinMaterial, in: Circle()) }
                    .accessibilityLabel("更多").homeHitRegion(.control("more"))
            }
            HomeModePicker(selection: model.mode) { next in
                withAnimation(AppPalette.motion(reduced: reduceMotion)) { model.selectMode(next) }
            }.homeHitRegion(.control("modePicker"))
        }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
    }

    private func page(_ kind: ItemKind, width: CGFloat) -> some View {
        let active = model.mode == kind
        let base: CGFloat = active ? 0 : (kind == .plan ? width : -width)
        return HomeModeList(mode: kind, interaction: interaction)
            .offset(x: reduceMotion ? 0 : base + interaction.pageOffset(mode: model.mode, width: width))
            .opacity(reduceMotion && !active ? 0 : 1)
            .allowsHitTesting(active).accessibilityHidden(!active)
    }

    private var primaryActions: some View {
        VStack(spacing: 6) {
            if model.mode == .idea {
                Button("我现在有空") { sheet = .freeTime }.frame(maxWidth: .infinity, minHeight: 44)
                    .homeHitRegion(.control("freeTime"))
            }
            Button { captureKind = model.mode; sheet = .capture } label: {
                Label(model.mode == .idea ? "记一下" : "新计划", systemImage: "plus")
            }.buttonStyle(FullWidthActionStyle(kind: model.mode, prominent: true))
                .accessibilityIdentifier("capturePrimary").homeHitRegion(.control("capture"))
        }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 12)
    }

    @ViewBuilder private var notificationStatus: some View {
        if model.notificationAccess == .denied {
            HStack { Text("通知未开启"); Spacer(); Button("前往设置") { openNotificationSettings() }.frame(minHeight: 44)
                    .homeHitRegion(.control("notificationSettings")) }.font(.subheadline).padding(.horizontal, 20)
        } else if model.workspace.notificationOnboarding.offerEnable {
            HStack {
                Text("通知已允许，提醒已暂停")
                Spacer()
                Button("开启提醒") { var value = model.preferences; value.enabled = true; model.attempt { try model.savePreferences(value) } }
                    .frame(minHeight: 44).homeHitRegion(.control("enableReminders"))
                Button("关闭") {
                    model.attempt { var next = model.workspace; next.notificationOnboarding.offerEnable = false; try model.commit(next) }
                }.frame(minHeight: 44).accessibilityLabel("关闭开启提醒提示").homeHitRegion(.control("dismissReminders"))
            }.font(.subheadline).padding(.horizontal, 20)
        }
    }

    private func handle(_ event: HomePanEvent, width: CGFloat) {
        switch event.state {
        case .began: interaction.begin(event.target); interaction.move(event.translation)
        case .changed: interaction.move(event.translation)
        case .ended, .cancelled, .failed:
            interaction.move(event.translation)
            withAnimation(AppPalette.motion(reduced: reduceMotion)) {
                if let mode = interaction.finish(mode: model.mode, width: width, velocity: event.velocity,
                                                  cancelled: event.state != .ended) { model.selectMode(mode) }
            }
        default: break
        }
    }
}
