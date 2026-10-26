// 所属层级：L3 外交层（界面）
// 文件职责：随模式变色的可点选分段入口。
// 输入：当前模式、提交闭包；输出：单次模式选择。
// 依赖：视觉样式；选择状态同时向无障碍公开。
import SwiftUI

struct HomeModePicker: View {
    let selection: ItemKind
    var select: (ItemKind) -> Void
    @Namespace private var marker
    var body: some View {
        HStack(spacing: 4) {
            ForEach(ItemKind.allCases) { kind in
                Button { select(kind) } label: {
                    Text(kind.label).font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(selection == kind ? Color("OnAccent") : .primary)
                        .background {
                            if selection == kind {
                                RoundedRectangle(cornerRadius: 13).fill(AppPalette.accent(kind))
                                    .matchedGeometryEffect(id: "selection", in: marker)
                            }
                        }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityIdentifier("homeMode/\(kind.rawValue)")
                    .accessibilityValue(selection == kind ? "已选中" : "未选中")
                    .accessibilityAddTraits(selection == kind ? [.isSelected] : [])
            }
        }.padding(4).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17))
            .accessibilityElement(children: .contain).accessibilityLabel("内容模式")
    }
}
