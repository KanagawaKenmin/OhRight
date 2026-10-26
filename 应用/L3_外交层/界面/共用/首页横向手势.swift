// 所属层级：L3 外交层（界面）
// 文件职责：桥接单指方向锁定识别器，协调首页横滑与列表竖滑。
// 输入：实时命中边界、启用状态；输出：起点固定的拖动事件。
// 依赖：UIKit、SwiftUI 官方手势桥接；系统管理识别器安装与卸载。
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

struct HomePanEvent {
    let target: HomeDragTarget
    let translation: CGFloat
    let velocity: CGFloat
    let state: UIGestureRecognizer.State
}

struct HomePanGesture: UIGestureRecognizerRepresentable {
    var regions: [HomeHitRegion: CGRect]
    var enabled: Bool
    var onEvent: (HomePanEvent) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator(self, converter: converter) }
    func makeUIGestureRecognizer(context: Context) -> HorizontalHomePan {
        let recognizer = HorizontalHomePan()
        recognizer.maximumNumberOfTouches = 1
        recognizer.cancelsTouchesInView = true
        recognizer.delegate = context.coordinator
        recognizer.isEnabled = enabled
        return recognizer
    }
    func updateUIGestureRecognizer(_ recognizer: HorizontalHomePan, context: Context) {
        context.coordinator.parent = self
        context.coordinator.converter = context.converter
        recognizer.isEnabled = enabled
    }
    func handleUIGestureRecognizerAction(_ recognizer: HorizontalHomePan, context: Context) {
        guard let target = context.coordinator.target else { return }
        onEvent(HomePanEvent(target: target, translation: recognizer.translation(in: recognizer.view).x,
                             velocity: recognizer.velocity(in: recognizer.view).x, state: recognizer.state))
        if [.ended, .cancelled, .failed].contains(recognizer.state) { context.coordinator.target = nil }
    }

    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: HomePanGesture
        var converter: CoordinateSpaceConverter
        var target: HomeDragTarget?
        init(_ parent: HomePanGesture, converter: CoordinateSpaceConverter) {
            self.parent = parent; self.converter = converter
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard parent.enabled, !UIAccessibility.isVoiceOverRunning else { return false }
            let point = converter.convert(globalPoint: touch.location(in: nil), to: .named("homeGestures"))
            guard let owner = HomeInteraction.hit(at: point, regions: parent.regions) else { return false }
            var view = touch.view
            while let candidate = view {
                if candidate is UITextView || candidate is UITextField { return false }
                // 卡片现在是标准按钮：起点明确归属卡片时允许横滑，其他原生控件仍不接管。
                if candidate is UIControl && owner == .page { return false }
                if candidate === gestureRecognizer.view { break }
                view = candidate.superview
            }
            // 保留最外侧系统边缘手势。页面跨区移动后不重新命中。
            let bounds = gestureRecognizer.view?.bounds ?? .zero
            let localX = touch.location(in: gestureRecognizer.view).x
            guard localX >= 16, localX <= bounds.width - 16 else { return false }
            target = owner
            return true
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let delta = pan.translation(in: pan.view)
            return abs(delta.x) > abs(delta.y) * 1.3 && target != nil
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // 只让竖向列表等方向判定；横向滚动容器和系统边缘手势不建立依赖。
            guard let scroll = otherGestureRecognizer.view as? UIScrollView,
                  otherGestureRecognizer === scroll.panGestureRecognizer,
                  !(scroll is UITextView) else { return false }
            return scroll.contentSize.width <= scroll.bounds.width + 1 && !scroll.alwaysBounceHorizontal
        }
    }
}

/// 在 UIKit 进入 began 前拒绝竖向或含糊的斜向拖动，使列表及时接管。
final class HorizontalHomePan: UIPanGestureRecognizer {
    private var origin: CGPoint?
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        origin = touches.first?.location(in: view)
        super.touchesBegan(touches, with: event)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible, let origin, let point = touches.first?.location(in: view) {
            let x = point.x - origin.x, y = point.y - origin.y
            guard hypot(x, y) >= 10 else { return }
            if abs(x) <= abs(y) * 1.3 { state = .failed; return }
        }
        super.touchesMoved(touches, with: event)
    }
    override func reset() { origin = nil; super.reset() }
}

struct HomeBackgroundTap: UIGestureRecognizerRepresentable {
    var regions: [HomeHitRegion: CGRect]
    var enabled: Bool
    var action: () -> Void
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator(self, converter: converter) }
    func makeUIGestureRecognizer(context: Context) -> UITapGestureRecognizer {
        let recognizer = UITapGestureRecognizer()
        recognizer.delegate = context.coordinator
        recognizer.cancelsTouchesInView = false
        recognizer.isEnabled = enabled
        return recognizer
    }
    func updateUIGestureRecognizer(_ recognizer: UITapGestureRecognizer, context: Context) {
        context.coordinator.parent = self; context.coordinator.converter = context.converter
        recognizer.isEnabled = enabled
    }
    func handleUIGestureRecognizerAction(_ recognizer: UITapGestureRecognizer, context: Context) {
        if recognizer.state == .ended { action() }
    }
    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: HomeBackgroundTap
        var converter: CoordinateSpaceConverter
        init(_ parent: HomeBackgroundTap, converter: CoordinateSpaceConverter) {
            self.parent = parent; self.converter = converter
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard parent.enabled else { return false }
            let point = converter.convert(globalPoint: touch.location(in: nil), to: .named("homeGestures"))
            return HomeInteraction.hit(at: point, regions: parent.regions) == .page
        }
    }
}
