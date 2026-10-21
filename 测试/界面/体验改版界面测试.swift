// 测试边界：验证长按后实际星标/归档撤销、转换取消与保存、即时设置。
// 输入：独立内存 App；输出：实际结果断言；不冒充真机手势验收。
import XCTest

final class ExperienceUITests: XCTestCase {
    @MainActor private func open() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        return app
    }

    @MainActor private func capture(_ app: XCUIApplication, text: String) -> XCUIElement {
        let add = app.buttons["capturePrimary"]
        XCTAssertTrue(add.waitForExistence(timeout: 10)); add.tap()
        let field = app.descendants(matching: .any).matching(identifier: "itemText").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(text)
        app.buttons["saveItem"].tap()
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "itemCard/idea/")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        return card
    }

    @MainActor func testLongPressStarArchiveAndDeleteCanUndo() {
        let app = open(), card = capture(app, text: "需要处理的琐事")
        card.press(forDuration: 0.8)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "itemDetailTitle").firstMatch.exists)
        let star = app.buttons["星标"]
        XCTAssertTrue(star.waitForExistence(timeout: 3)); star.tap()
        XCTAssertTrue(app.buttons["取消星标"].waitForExistence(timeout: 3))
        app.buttons["归档"].tap()
        XCTAssertFalse(card.exists)
        app.buttons["撤销"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        card.press(forDuration: 0.8); app.buttons["删除"].tap()
        XCTAssertFalse(card.exists)
        app.buttons["撤销"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        card.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "itemDetailTitle").firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor func testConversionCancelThenSaveKeepsTitleAndIdentity() {
        let app = open(), card = capture(app, text: "从琐事开始")
        let id = card.identifier.components(separatedBy: "/").last!
        card.tap()
        app.buttons["转为计划"].tap()
        app.navigationBars["转为计划"].buttons["关闭"].tap()
        XCTAssertTrue(app.navigationBars["琐事"].waitForExistence(timeout: 3))
        app.buttons["转为计划"].tap()
        app.buttons["saveItem"].tap()
        XCTAssertTrue(app.navigationBars["计划"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "itemDetailTitle").firstMatch.label, "从琐事开始")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let converted = app.descendants(matching: .any).matching(identifier: "itemCard/plan/\(id)").firstMatch
        XCTAssertTrue(converted.waitForExistence(timeout: 3))
    }

    @MainActor func testSettingsSaveImmediatelyAndHistoryExcludesActive() {
        let app = open()
        _ = capture(app, text: "只在搜索里出现")
        app.buttons["更多"].tap(); app.buttons["历史记录"].tap()
        XCTAssertTrue(app.navigationBars["历史记录"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["只在搜索里出现"].exists)
        app.buttons["完成"].tap()
        app.buttons["更多"].tap(); app.buttons["搜索"].tap()
        XCTAssertTrue(app.staticTexts["只在搜索里出现"].waitForExistence(timeout: 3))
        app.buttons["完成"].tap()
        app.buttons["更多"].tap(); app.buttons["设置"].tap()
        app.buttons["notificationSettings"].tap()
        let sound = app.switches["声音"]
        if !sound.isHittable { app.swipeUp() }
        XCTAssertTrue(sound.waitForExistence(timeout: 3))
        let before = sound.value as? String
        sound.tap()
        XCTAssertNotEqual(sound.value as? String, before)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["关闭"].tap()
        app.buttons["更多"].tap(); app.buttons["设置"].tap(); app.buttons["notificationSettings"].tap()
        if !sound.isHittable { app.swipeUp() }
        XCTAssertNotEqual(sound.value as? String, before)
    }
}
