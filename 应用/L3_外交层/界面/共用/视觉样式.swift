// 所属层级：L3 外交层（界面）
// 文件职责：两模式静态背景、表面和短交互动画。
// 输入：模式、系统外观；输出：纯视觉表现。
// 依赖：SwiftUI、资源色；装饰不参与命中或持续刷新。
import SwiftUI

enum AppPalette {
    static let teal = Color("IdeaAccent")
    static let red = Color("PlanAccent")
    static func accent(_ kind: ItemKind) -> Color { kind == .idea ? teal : red }
    static func surface(_ kind: ItemKind, dark: Bool) -> Color {
        dark ? Color(hex: kind == .idea ? 0x203A30 : 0x402F24) : .white
    }
    static func soft(_ kind: ItemKind, dark: Bool) -> Color {
        Color(hex: dark ? (kind == .idea ? 0x294A3E : 0x563B29) : (kind == .idea ? 0xD3E8DF : 0xF3D9C5))
    }
    static func ink(dark: Bool) -> Color { Color(hex: dark ? 0xF1F4F2 : 0x202B27) }
    static func motion(reduced: Bool) -> Animation? { reduced ? nil : .easeOut(duration: 0.22) }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

struct ModeBackground: View {
    let mode: ItemKind
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let dark = scheme == .dark
        let top: UInt32 = dark ? (mode == .idea ? 0x152922 : 0x302319) : (mode == .idea ? 0xDDEFE8 : 0xF7E4D4)
        let bottom: UInt32 = dark ? top : (mode == .idea ? 0xF0F7F3 : 0xFFF4E8)
        LinearGradient(colors: [Color(hex: top), Color(hex: bottom)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct ItemSurface: ViewModifier {
    let kind: ItemKind
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.padding(18)
            .foregroundStyle(AppPalette.ink(dark: scheme == .dark))
            .background(AppPalette.surface(kind, dark: scheme == .dark), in: RoundedRectangle(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.primary.opacity(0.04), lineWidth: 1) }
    }
}

struct AppFeedback: ViewModifier {
    @Environment(AppModel.self) private var model
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if let text = model.message ?? model.notice {
                HStack(alignment: .top) {
                    Text(text).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                    if model.undoItem != nil { Button("撤销") { model.undoQuickAction() }.frame(minHeight: 44) }
                    Button {
                        model.message = nil
                        model.notice = nil
                        model.undoItem = nil
                    } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                        .accessibilityLabel("关闭提示")
                }
                .padding(.leading, 16).padding(.trailing, 4)
                .background(model.message == nil ? Color.teal.opacity(0.13) : Color.orange.opacity(0.16))
            }
        }
    }
}

extension View {
    func appFeedback() -> some View { modifier(AppFeedback()) }
    func itemCard(_ kind: ItemKind) -> some View { modifier(ItemSurface(kind: kind)) }
}
