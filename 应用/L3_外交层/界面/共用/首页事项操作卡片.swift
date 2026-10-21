// 所属层级：L3 外交层（界面）
// 文件职责：互斥识别长按/点击并展示圆形快捷动作。
// 输入：选中事项；输出：导航、星标、可撤销状态命令。
// 依赖：AppModel；窄屏和辅助大字体将操作放在卡片下方。
import SwiftUI

struct HomeActionCard: View {
    let item: Item
    @Binding var selected: UUID?
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Group {
            if selected == item.id {
                if typeSize.isAccessibilitySize { VStack(alignment: .leading) { card; actions } }
                else {
                    ViewThatFits(in: .horizontal) {
                        HStack { card.frame(minWidth: 240); actions.fixedSize() }
                        VStack(alignment: .leading) { card; actions }
                    }
                }
            } else { card }
        }
    }
    private var card: some View {
        ItemCard(item: item)
            .contentShape(Rectangle())
            .gesture(LongPressGesture(minimumDuration: 0.45).exclusively(before: TapGesture()).onEnded { value in
                switch value {
                case .first: selected = item.id
                case .second:
                    if selected != nil { selected = nil } else { model.path.append(item.id) }
                }
            })
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("itemCard/\(item.kind.rawValue)/\(item.id.uuidString)")
            .accessibilityAction { model.path.append(item.id) }
            .accessibilityAction(named: item.isStarred ? "取消星标" : "星标") { model.attempt { try model.toggleStar(item.id) } }
            .accessibilityAction(named: "归档") { perform(.archive) }
            .accessibilityAction(named: "删除") { perform(.delete) }
    }
    private var actions: some View {
        VStack(spacing: 8) {
            circle(item.isStarred ? "取消星标" : "星标", icon: item.isStarred ? "star.fill" : "star") {
                model.attempt { try model.toggleStar(item.id) }
            }
            circle("归档", icon: "archivebox") { perform(.archive) }
            circle("删除", icon: "trash") { perform(.delete) }
        }
    }
    private func circle(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 44, height: 44).background(.regularMaterial, in: Circle()) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }
    private func perform(_ action: LifecycleAction) {
        if model.attempt({ try model.quickAction(item.id, action: action) }) { selected = nil }
    }
}

struct HomeBlankArea: View {
    @Environment(AppModel.self) private var model
    @Binding var selected: UUID?
    var height: CGFloat = 90
    var body: some View {
        Color.clear.frame(height: height).contentShape(Rectangle())
            .onTapGesture { selected = nil }
            .gesture(DragGesture(minimumDistance: 35).onEnded { drag in
                let x = drag.translation.width, y = drag.translation.height
                guard drag.startLocation.x > 24, abs(x) > 60, abs(x) > abs(y) * 1.8 else { return }
                selected = nil
                if x < 0 { model.selectMode(.plan) } else { model.selectMode(.idea) }
            })
            .accessibilityHidden(true)
    }
}
