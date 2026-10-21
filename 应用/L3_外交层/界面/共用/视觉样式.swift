// 所属层级：L3 外交层（界面）
// 文件职责：提供两模式色彩、稳定卡片和可关闭流动装饰。
// 输入：模式、系统无障碍与电量；输出：纯视觉表现。
// 依赖：SwiftUI；装饰不承载文本与交互。
import SwiftUI

enum AppPalette {
    static let teal = Color("IdeaAccent")
    static let red = Color("PlanAccent")
    static func accent(_ kind: ItemKind) -> Color { kind == .idea ? teal : red }
}

struct ModeBackground: View {
    let mode: ItemKind
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scene
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        ZStack {
            (scheme == .dark ? Color(red: 0.08, green: 0.09, blue: 0.10) :
                Color(red: 0.97, green: 0.96, blue: 0.95))
            if mode == .idea && !reduceTransparency {
                TimelineView(.animation(minimumInterval: 0.1, paused: reduceMotion || lowPower || scene != .active)) { context in
                    let phase = reduceMotion || lowPower ? 0 : context.date.timeIntervalSinceReferenceDate / 7
                    GeometryReader { geometry in
                        ZStack {
                            Circle().fill(Color(red: 0.61, green: 0.83, blue: 0.75))
                                .frame(width: 280, height: 280)
                                .offset(x: -110 + sin(phase) * 18, y: 20)
                            Ellipse().fill(Color(red: 0.78, green: 0.72, blue: 0.90))
                                .frame(width: 300, height: 350)
                                .offset(x: geometry.size.width - 210, y: 260 + cos(phase) * 20)
                        }
                    }.blur(radius: 65).opacity(scheme == .dark ? 0.15 : 0.27)
                }
            }
        }
        .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
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
    func itemCard(_ kind: ItemKind) -> some View {
        self.padding(20)
            .background(.background, in: RoundedRectangle(cornerRadius: kind == .idea ? 26 : 6))
            .overlay {
                RoundedRectangle(cornerRadius: kind == .idea ? 26 : 6)
                    .strokeBorder(.primary.opacity(kind == .idea ? 0.05 : 0.17), lineWidth: 1)
            }
    }
}
