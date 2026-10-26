// 测试边界：不启动 App，验证手势归属、边界、取消恢复与单张展开。
// 输入：虚拟矩形、位移和速度；输出：交互状态断言。
// 依赖：应用测试 target；真实识别器与滚动协调仍由 UI/真机验收。
import Foundation
import Testing
@testable import OhRight

@MainActor struct HomeInteractionTests {
    @Test func hitRegionsRespectCardsControlsAndClippedRows() {
        let id = UUID()
        let regions: [HomeHitRegion: CGRect] = [
            .list(.idea): CGRect(x: 0, y: 100, width: 390, height: 500),
            .card(id): CGRect(x: 20, y: 80, width: 350, height: 140),
            .control("more"): CGRect(x: 326, y: 10, width: 44, height: 44),
            .rowControl(id, "star"): CGRect(x: 200, y: 80, width: 58, height: 80)
        ]
        #expect(HomeInteraction.hit(at: CGPoint(x: 30, y: 180), regions: regions) == .card(id))
        #expect(HomeInteraction.hit(at: CGPoint(x: 200, y: 90), regions: regions) == .page)
        #expect(HomeInteraction.hit(at: CGPoint(x: 10, y: 180), regions: regions) == .page)
        #expect(HomeInteraction.hit(at: CGPoint(x: 330, y: 30), regions: regions) == nil)
        #expect(HomeInteraction.hit(at: CGPoint(x: 210, y: 120), regions: regions) == nil)
    }

    @Test func pageSwitchesOnlyAtFinishAndNeverWraps() {
        let value = HomeInteraction()
        value.begin(.page); value.move(-120)
        #expect(value.pageOffset(mode: .idea, width: 390) == -120)
        #expect(value.finish(mode: .idea, width: 390, velocity: 0, cancelled: false) == .plan)
        #expect(value.target == nil && value.translation == 0)
        value.begin(.page); value.move(-160)
        #expect(abs(value.pageOffset(mode: .plan, width: 390) + 19.2) < 0.001)
        #expect(value.finish(mode: .plan, width: 390, velocity: -500, cancelled: false) == nil)
        value.begin(.page); value.move(110)
        #expect(value.finish(mode: .plan, width: 390, velocity: 0, cancelled: false) == .idea)
    }

    @Test func shortPageDragReturnsWithoutSwitchingAndFlickCanComplete() {
        let value = HomeInteraction()
        value.begin(.page); value.move(-30)
        #expect(value.finish(mode: .idea, width: 390, velocity: 0, cancelled: false) == nil)
        value.begin(.page); value.move(-30)
        #expect(value.finish(mode: .idea, width: 390, velocity: -600, cancelled: false) == .plan)
    }

    @Test func rowNeverSwitchesPageAndOnlyOneRowCanRemainOpen() {
        let value = HomeInteraction(), a = UUID(), b = UUID()
        value.begin(.card(a)); value.move(-180)
        #expect(value.pageOffset(mode: .idea, width: 390) == 0)
        #expect(value.finish(mode: .idea, width: 390, velocity: 0, cancelled: false) == nil)
        #expect(value.openedItemID == a)
        value.begin(.card(b)); value.move(-150)
        #expect(value.cardOffset(a) == 0)
        #expect(value.finish(mode: .idea, width: 390, velocity: 0, cancelled: false) == nil)
        #expect(value.openedItemID == b && value.cardOffset(a) == 0)
        value.begin(.card(b)); value.move(160)
        _ = value.finish(mode: .idea, width: 390, velocity: 0, cancelled: false)
        #expect(value.openedItemID == nil)
    }

    @Test func cancelRestoresOriginalRowAndNeverCommitsMode() {
        let value = HomeInteraction(), id = UUID()
        value.openedItemID = id
        value.begin(.page); value.move(-200)
        #expect(value.openedItemID == nil)
        #expect(value.finish(mode: .idea, width: 390, velocity: -900, cancelled: true) == nil)
        #expect(value.openedItemID == id)
        value.begin(.card(id)); value.move(100)
        _ = value.finish(mode: .idea, width: 390, velocity: 500, cancelled: true)
        #expect(value.cardOffset(id) == -HomeInteraction.railWidth)
        value.reset()
        #expect(value.openedItemID == nil && value.target == nil)
    }
}
