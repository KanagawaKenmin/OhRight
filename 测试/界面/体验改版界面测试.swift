// 测试边界：验证卡片左滑后星标/归档撤销、转换取消与保存、历史/搜索范围。
// 输入：独立内存 App；输出：实际结果断言；不冒充真机手势验收。
import XCTest

final class ExperienceUITests: XCTestCase {
    @MainActor private func open(fixture: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-fixture=\(fixture)", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        return app
    }

    @MainActor private func fixtureCard(_ app: XCUIApplication) -> XCUIElement {
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "itemCard/idea/")).firstMatch
        require(card, in: app, stage: "隔离场景记录已准备")
        return card
    }

    @MainActor func testSwipeStarArchiveAndDeleteCanUndo() {
        let app = open(fixture: "quick-actions"), card = fixtureCard(app)
        let id = card.identifier.components(separatedBy: "/").last!
        card.swipeLeft(velocity: .slow)
        XCTAssertFalse(app.staticTexts["itemDetailTitle"].firstMatch.exists)
        let star = app.buttons["itemAction/star/\(id)"]
        require(star, in: app, stage: "卡片单次左滑展开星标"); star.tap()
        wait(NSPredicate(format: "value CONTAINS %@", "已星标"), on: card, in: app, stage: "星标已保存")
        card.swipeLeft(velocity: .slow)
        XCTAssertEqual(app.buttons["itemAction/star/\(id)"].label, "取消星标")
        let archive = app.buttons["itemAction/archive/\(id)"]
        require(archive, in: app, stage: "左滑展开归档"); archive.tap()
        wait(NSPredicate(format: "exists == false"), on: card, in: app, stage: "归档移出首页")
        app.buttons["撤销"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        card.swipeLeft(velocity: .slow)
        let delete = app.buttons["itemAction/delete/\(id)"]
        require(delete, in: app, stage: "左滑展开删除"); delete.tap()
        wait(NSPredicate(format: "exists == false"), on: card, in: app, stage: "删除移出首页")
        app.buttons["撤销"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        card.tap()
        XCTAssertTrue(app.staticTexts["itemDetailTitle"].firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor private func require(_ element: XCUIElement, in app: XCUIApplication, stage: String) {
        wait(NSPredicate(format: "exists == true AND hittable == true"), on: element, in: app, stage: stage)
    }

    @MainActor private func wait(_ predicate: NSPredicate, on element: XCUIElement, in app: XCUIApplication, stage: String) {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        guard XCTWaiter.wait(for: [expectation], timeout: 4) != .completed else { return }
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = stage; screenshot.lifetime = .keepAlways
        let tree = XCTAttachment(string: app.debugDescription); tree.name = "失败界面树"; tree.lifetime = .keepAlways
        add(screenshot); add(tree)
        print("UI verification failure: \(stage)\n\(app.debugDescription)")
        XCTFail(stage)
    }

    @MainActor func testConversionCancelThenSaveKeepsTitleAndIdentity() {
        let app = open(fixture: "conversion"), card = fixtureCard(app)
        let id = card.identifier.components(separatedBy: "/").last!
        card.tap()
        let convert = app.buttons["convertToPlan"]
        XCTAssertGreaterThan(convert.frame.width, app.frame.width * 0.75)
        XCTAssertGreaterThanOrEqual(convert.frame.height, 52)
        convert.tap()
        app.navigationBars["转为计划"].buttons["关闭"].tap()
        XCTAssertTrue(app.navigationBars["琐事"].waitForExistence(timeout: 3))
        app.buttons["convertToPlan"].tap()
        app.buttons["saveItem"].tap()
        XCTAssertTrue(app.navigationBars["计划"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["itemDetailTitle"].firstMatch.label, "从琐事开始")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let converted = app.buttons.matching(identifier: "itemCard/plan/\(id)").firstMatch
        XCTAssertTrue(converted.waitForExistence(timeout: 3))
    }

    @MainActor func testHistoryExcludesActiveAndSearchIncludesIt() {
        let app = open(fixture: "library")
        _ = fixtureCard(app)
        app.buttons["更多"].tap(); app.buttons["历史记录"].tap()
        XCTAssertTrue(app.navigationBars["历史记录"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["只在搜索里出现"].exists)
        app.buttons["完成"].tap()
        app.buttons["更多"].tap(); app.buttons["搜索"].tap()
        XCTAssertTrue(app.staticTexts["只在搜索里出现"].waitForExistence(timeout: 3))
        app.buttons["完成"].tap()
    }
}
