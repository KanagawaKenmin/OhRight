// 测试边界：模拟器核心录入路径与两模式截图。
// 输入：独立内存测试环境；输出：断言与 xcresult 截图。
// 不代表真实手机通知、签名或续签已经通过。
import XCTest

final class ModeUITests: XCTestCase {
    @MainActor func testCaptureAndBothModes() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        app.launch()
        let capture = app.buttons["capturePrimary"]
        XCTAssertTrue(capture.waitForExistence(timeout: 10))
        capture.tap()
        let field = app.descendants(matching: .any).matching(identifier: "itemText").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("A small spark")
        app.buttons["saveItem"].tap()
        XCTAssertTrue(app.staticTexts["A small spark"].waitForExistence(timeout: 5))
        attach(app, name: "琐事模式")
        app.segmentedControls.buttons["计划"].tap()
        capture.tap()
        let planField = app.descendants(matching: .any).matching(identifier: "itemText").firstMatch
        XCTAssertTrue(planField.waitForExistence(timeout: 5))
        planField.tap()
        planField.typeText("Prepare materials")
        app.buttons["saveItem"].tap()
        XCTAssertTrue(app.staticTexts["Prepare materials"].waitForExistence(timeout: 5))
        attach(app, name: "计划模式")
    }

    @MainActor private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
