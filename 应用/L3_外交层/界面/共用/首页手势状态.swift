// 所属层级：L3 外交层（界面）
// 文件职责：首页单笔拖动归属、跟手位移与打开卡片状态。
// 输入：起点归属、位移与速度；输出：表现状态、松手后的可选目标模式。
// 依赖：SwiftUI、领域模式；不提交存储，不持有界面或系统识别器。
import SwiftUI
import Observation

enum HomeDragTarget: Equatable, Sendable { case page, card(UUID) }
enum HomeHitRegion: Hashable, Sendable { case card(UUID), rowControl(UUID, String), control(String), list(ItemKind) }

@MainActor @Observable final class HomeInteraction {
    static let railWidth: CGFloat = 194
    var openedItemID: UUID?
    private(set) var target: HomeDragTarget?
    private(set) var translation: CGFloat = 0
    private var originalOpenedItemID: UUID?

    func begin(_ next: HomeDragTarget) {
        target = next
        originalOpenedItemID = openedItemID
        if case .page = next { openedItemID = nil }
        else if case .card(let id) = next, openedItemID != id { openedItemID = nil }
        translation = 0
    }

    func move(_ value: CGFloat) { guard target != nil else { return }; translation = value }

    func cardOffset(_ id: UUID) -> CGFloat {
        if target == .card(id) {
            let base = originalOpenedItemID == id ? -Self.railWidth : 0
            return max(-Self.railWidth, min(0, base + translation))
        }
        return openedItemID == id ? -Self.railWidth : 0
    }

    func pageOffset(mode: ItemKind, width: CGFloat) -> CGFloat {
        guard target == .page else { return 0 }
        let outward = mode == .idea ? translation > 0 : translation < 0
        return outward ? translation * 0.12 : max(-width, min(width, translation))
    }

    /// 松手只返回模式；由首页在动画事务内执行一次业务提交。取消不提交。
    func finish(mode: ItemKind, width: CGFloat, velocity: CGFloat, cancelled: Bool) -> ItemKind? {
        var next: ItemKind?
        if cancelled { openedItemID = originalOpenedItemID }
        else if case .card(let id) = target {
            let base = originalOpenedItemID == id ? -Self.railWidth : 0
            openedItemID = base + translation + velocity * 0.10 < -Self.railWidth * 0.4 ? id : nil
        } else if target == .page {
            let projected = translation + velocity * 0.12
            let threshold = max(44, width * 0.2)
            if mode == .idea && min(translation, projected) < -threshold { next = .plan }
            if mode == .plan && max(translation, projected) > threshold { next = .idea }
        }
        target = nil
        translation = 0
        originalOpenedItemID = nil
        return next
    }

    func reset() {
        target = nil; translation = 0; openedItemID = nil; originalOpenedItemID = nil
    }

    static func hit(at point: CGPoint, regions: [HomeHitRegion: CGRect]) -> HomeDragTarget? {
        // 控件始终优先于重叠卡片；卡片以整行矩形而非文字轮廓命中。
        let inList = regions.contains { key, rect in
            if case .list = key { return rect.contains(point) }
            return false
        }
        for (region, frame) in regions where frame.contains(point) {
            if case .control = region { return nil }
            if case .rowControl(let id, _) = region, inList,
               regions[.card(id)]?.contains(point) == true { return nil }
        }
        for (region, frame) in regions where frame.contains(point) {
            if case .card(let id) = region, inList { return .card(id) }
        }
        return .page
    }
}

struct HomeHitRegions: PreferenceKey {
    static var defaultValue: [HomeHitRegion: CGRect] { [:] }
    static func reduce(value: inout [HomeHitRegion: CGRect], nextValue: () -> [HomeHitRegion: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func homeHitRegion(_ region: HomeHitRegion, enabled: Bool = true) -> some View {
        background {
            if enabled {
                GeometryReader { proxy in
                    Color.clear.preference(key: HomeHitRegions.self, value: [region: proxy.frame(in: .named("homeGestures"))])
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
}
