// 测试边界：模拟器核心录入路径与两模式截图。
// 输入：独立内存测试环境；输出：断言与 xcresult 截图。
// 不代表真实手机通知、签名或续签已经通过。
import XCTest

final class ModeUITests: XCTestCase {
    @MainActor func testCaptureAndBothModes() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        app.launch()
        captureAndVerify(app, kind: "idea", text: "A small spark", screenshotName: "琐事模式")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let plans = app.segmentedControls.buttons["计划"]
        require(plans, in: app, stage: "返回首页并切换计划")
        plans.tap()
        captureAndVerify(app, kind: "plan", text: "Prepare materials", screenshotName: "计划模式")
    }

    // 按卡片标识定位后进入详情核对原文，不能依赖合并节点中的独立 StaticText。
    @MainActor private func captureAndVerify(_ app: XCUIApplication, kind: String,
                                            text: String, screenshotName: String) {
        let capture = app.buttons["capturePrimary"]
        require(capture, in: app, stage: "\(kind)：打开记录入口")
        capture.tap()
        let field = app.descendants(matching: .any).matching(identifier: "itemText").firstMatch
        require(field, in: app, stage: "\(kind)：显示输入框")
        field.tap()
        field.typeText(text)
        guard field.value as? String == text else {
            fail(app, stage: "\(kind)：输入内容不一致，实际值：\(String(describing: field.value))")
            return
        }
        app.buttons["saveItem"].tap()
        let card = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "itemCard/\(kind)/")).firstMatch
        require(card, in: app, stage: "\(kind)：保存后显示对应类别卡片")
        attach(app, name: screenshotName)
        card.tap()
        let title = app.descendants(matching: .any).matching(identifier: "itemDetailTitle").firstMatch
        require(title, in: app, stage: "\(kind)：打开保存的事项详情")
        guard title.label == text else {
            fail(app, stage: "\(kind)：保存后标题不一致，实际标题：\(title.label)")
            return
        }
    }

    @MainActor private func require(_ element: XCUIElement, in app: XCUIApplication, stage: String) {
        if !element.waitForExistence(timeout: 10) { fail(app, stage: stage) }
    }

    @MainActor private func fail(_ app: XCUIApplication, stage: String) {
        attach(app, name: "失败：\(stage)")
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "失败界面结构：\(stage)"
        tree.lifetime = .keepAlways
        add(tree)
        print("UI verification failure: \(stage)\n\(app.debugDescription)")
        XCTFail(stage)
    }

    @MainActor private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
