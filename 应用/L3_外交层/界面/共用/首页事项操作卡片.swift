// 所属层级：L3 外交层（界面）
// 文件职责：固定行高的跟手卡片、横排圆形动作及辅助操作。
// 输入：事项、首页统一交互状态；输出：导航与可撤销命令。
// 依赖：AppModel、首页手势状态；不自行识别横滑或改变卡片布局。
import SwiftUI

struct HomeActionCard: View {
    let item: Item
    let interaction: HomeInteraction
    var active: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var offset: CGFloat { interaction.cardOffset(item.id) }
    private var opened: Bool { interaction.openedItemID == item.id }
    private var progress: CGFloat { min(1, abs(offset) / HomeInteraction.railWidth) }

    var body: some View {
        ZStack(alignment: .trailing) {
            actions.opacity(Double(progress))
                .scaleEffect(reduceMotion ? 1 : 0.85 + progress * 0.15, anchor: .trailing)
                .allowsHitTesting(opened).accessibilityHidden(!opened)
            Button {
                if opened { settle { interaction.reset() } }
                else { interaction.reset(); model.path.append(item.id) }
            } label: {
                ItemCard(item: item, minimumHeight: typeSize.isAccessibilitySize ? 150 : 112)
                    .contentShape(Rectangle())
            }
                .buttonStyle(.plain)
                .accessibilityIdentifier("itemCard/\(item.kind.rawValue)/\(item.id.uuidString)")
                .accessibilityValue("\(item.isStarred ? "已星标；" : "")\(opened ? "操作已展开" : "操作已收起")")
                .accessibilityAction(named: item.isStarred ? "取消星标" : "星标") { toggleStar() }
                .accessibilityAction(named: "归档") { perform(.archive) }
                .accessibilityAction(named: "删除") { perform(.delete) }
                .offset(x: offset)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .homeHitRegion(.card(item.id), enabled: active)
    }

    private var actions: some View {
        HStack(alignment: .center, spacing: 10) {
            circle(item.isStarred ? "取消星标" : "星标", icon: item.isStarred ? "star.fill" : "star",
                   color: Color(hex: 0x986015), key: "star", action: toggleStar)
            circle("归档", icon: "archivebox", color: Color(hex: 0x247378), key: "archive") { perform(.archive) }
            circle("删除", icon: "trash", color: Color(hex: 0xBD3F33), key: "delete") { perform(.delete) }
        }.frame(width: HomeInteraction.railWidth)
    }

    private func circle(_ label: String, icon: String, color: Color, key: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 21, weight: .medium))
                    .frame(width: 48, height: 48).foregroundStyle(.white).background(color, in: Circle())
                Text(label).font(.caption2).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }.frame(width: 58).frame(minHeight: 80).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(label)
        .accessibilityIdentifier("itemAction/\(key)/\(item.id.uuidString)")
        .homeHitRegion(.rowControl(item.id, key), enabled: active && opened)
    }

    private func toggleStar() {
        if model.attempt({ try model.toggleStar(item.id) }) { settle { interaction.reset() } }
    }
    private func perform(_ action: LifecycleAction) {
        if model.attempt({ try model.quickAction(item.id, action: action) }) { settle { interaction.reset() } }
    }
    private func settle(_ action: () -> Void) { withAnimation(AppPalette.motion(reduced: reduceMotion), action) }
}
