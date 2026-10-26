// 所属层级：L3 外交层（界面）
// 文件职责：每种模式独立滚动、分组与卡片布局。
// 输入：模式和统一交互状态；输出：稳定列表、可见命中边界。
// 依赖：AppModel、卡片；隐藏页保留位置但不参与命中或辅助导航。
import SwiftUI

struct HomeModeList: View {
    let mode: ItemKind
    let interaction: HomeInteraction
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position: UUID?
    private var active: Bool { model.mode == mode }
    private var items: [Item] {
        model.workspace.items.filter { $0.kind == mode && [.active, .paused].contains($0.status) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text(mode == .idea ? "留住一个，还没想完的念头。" : "先往前走一小步。")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
                    .accessibilityIdentifier("homeSubtitle/\(mode.rawValue)")
                if items.isEmpty {
                    ContentUnavailableView(mode == .idea ? "还没有留下念头" : "还没有计划",
                        systemImage: mode == .idea ? "sparkles" : "square.stack",
                        description: Text(mode == .idea ? "先记下一句，没想完整也可以。" : "有了期限，再把它放到这里。"))
                        .frame(minHeight: 220)
                } else if mode == .idea { cards(items.sorted(by: LibraryQuery.starredFirst)) }
                else {
                    ForEach(PlanSection.allCases) { section in
                        let group = items.filter { PlanSection.of($0) == section }
                        if !group.isEmpty {
                            Text(section.rawValue).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 8)
                            cards(group.sorted { lhs, rhs in
                                if lhs.isStarred != rhs.isStarred { return lhs.isStarred }
                                return (lhs.deadline?.boundary ?? .distantFuture) < (rhs.deadline?.boundary ?? .distantFuture)
                            })
                        }
                    }
                }
                Color.clear.frame(height: 100).accessibilityHidden(true)
            }.scrollTargetLayout().padding(.horizontal, 20).padding(.bottom, 16)
        }
        .scrollPosition(id: $position)
        .onScrollPhaseChange { _, phase in
            if active && phase == .interacting {
                withAnimation(AppPalette.motion(reduced: reduceMotion)) { interaction.reset() }
            }
        }
        .homeHitRegion(.list(mode), enabled: active)
        .accessibilityIdentifier("homeList/\(mode.rawValue)")
    }

    private func cards(_ values: [Item]) -> some View {
        ForEach(values) { item in
            HomeActionCard(item: item, interaction: interaction, active: active).id(item.id)
        }
    }
}
