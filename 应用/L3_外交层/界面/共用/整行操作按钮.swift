// 所属层级：L3 外交层（界面）
// 文件职责：核心动作等宽按钮与紧凑工具按钮的统一样式。
// 输入：模式、强调级别和系统状态；输出：实际标签与命中区同步的按钮。
// 依赖：视觉样式；不承载业务命令。
import SwiftUI

struct FullWidthActionStyle: ButtonStyle {
    let kind: ItemKind
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        let dark = scheme == .dark
        configuration.label.font(.headline)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.horizontal, 16).padding(.vertical, 12)
            .frame(minHeight: prominent ? 54 : 52)
            .foregroundStyle(enabled ? (prominent ? Color("OnAccent") : AppPalette.accent(kind)) : Color.secondary)
            .background(enabled ? (prominent ? AppPalette.accent(kind) : AppPalette.soft(kind, dark: dark)) :
                AppPalette.soft(kind, dark: dark).opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

struct EditorToolStyle: ButtonStyle {
    let kind: ItemKind
    var selected = false
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.medium))
            .padding(.horizontal, 10).frame(minHeight: 44)
            .foregroundStyle(AppPalette.accent(kind))
            .background(selected ? AppPalette.soft(kind, dark: scheme == .dark) : .clear,
                        in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle()).opacity(configuration.isPressed ? 0.7 : 1)
    }
}
