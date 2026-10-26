// 测试边界：从首页直接验证声音单次切换与重进页面保持；独立内存库。
// 输入：真实 UI 手势；输出：精确值断言、截图、界面树与控件状态。
// 不证明杀进程后的磁盘持久化；失败不重试点击，不通过模型绕过界面。
import XCTest

final class SettingsUITests: XCTestCase {
    @MainActor func testReminderSettingsSaveImmediately() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        try enterSettings(app)
        let sound = try readySound(app)
        guard let before = sound.value as? String, ["0", "1"].contains(before) else {
            throw failure(app, stage: "切换前必须能读取 0 或 1")
        }
        let expected = before == "0" ? "1" : "0"
        print("UI_SOUND before=\(before) expected=\(expected)")
        attach(app, name: "声音切换前")
        sound.tap()
        try expectValue(expected, of: sound, in: app, stage: "单次点击后声音应切换到 \(expected)")
        attach(app, name: "声音切换后")

        let back = app.navigationBars["通知与提醒"].buttons.element(boundBy: 0)
        try tap(back, in: app, stage: "返回设置首页")
        try tap(app.navigationBars["设置"].buttons["关闭"], in: app, stage: "关闭设置")
        try enterSettings(app)
        let reopened = try readySound(app)
        try expectValue(expected, of: reopened, in: app, stage: "重进设置后仍应为 \(expected)")
    }

    @MainActor private func enterSettings(_ app: XCUIApplication) throws {
        try tap(app.buttons["更多"], in: app, stage: "打开更多")
        try tap(app.buttons["设置"], in: app, stage: "打开设置")
        try tap(app.buttons["notificationSettings"], in: app, stage: "进入通知与提醒")
    }

    @MainActor private func readySound(_ app: XCUIApplication) throws -> XCUIElement {
        let form = app.descendants(matching: .any).matching(identifier: "reminderSettingsForm").firstMatch
        guard form.waitForExistence(timeout: 10) else { throw failure(app, stage: "设置 Form 未出现") }
        let matches = app.switches.matching(identifier: "reminderSoundToggle")
        let sound = matches.firstMatch
        // Form 可能懒加载未入屏行；只在此容器内有限滚动，不根据 exists 认定可点击。
        for attempt in 0...4 {
            if sound.exists && sound.isEnabled && sound.isHittable && form.frame.contains(sound.frame) {
                guard matches.count == 1 else { throw failure(app, stage: "声音开关匹配不唯一") }
                return sound
            }
            if attempt < 4 { form.swipeUp() }
        }
        throw failure(app, stage: "声音开关在四次滚动后仍不可完整点击")
    }

    @MainActor private func tap(_ element: XCUIElement, in app: XCUIApplication, stage: String) throws {
        guard element.waitForExistence(timeout: 10) else { throw failure(app, stage: stage + "：目标不存在") }
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true AND enabled == true"), object: element)
        guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed else {
            throw failure(app, stage: stage + "：目标不可点击")
        }
        element.tap()
    }

    @MainActor private func expectValue(_ expected: String, of element: XCUIElement,
                                       in app: XCUIApplication, stage: String) throws {
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", expected), object: element)
        guard XCTWaiter.wait(for: [changed], timeout: 5) == .completed else {
            throw failure(app, stage: stage)
        }
        print("UI_SOUND observed=\(String(describing: element.value)) stage=\(stage)")
    }

    @MainActor private func failure(_ app: XCUIApplication, stage: String) -> NSError {
        let matches = app.switches.matching(identifier: "reminderSoundToggle")
        let sound = matches.firstMatch
        var state = "UI verification failure: \(stage); count=\(matches.count)"
        if sound.exists {
            state += "; frame=\(sound.frame) enabled=\(sound.isEnabled) hittable=\(sound.isHittable) value=\(String(describing: sound.value))"
        }
        let details = state + "\n" + app.debugDescription
        print(details)
        attach(app, name: "失败：\(stage)")
        let tree = XCTAttachment(string: details)
        tree.name = "失败状态与界面树"
        tree.lifetime = .keepAlways
        add(tree)
        return NSError(domain: "OhRightUIVerification", code: 1, userInfo: [NSLocalizedDescriptionKey: state])
    }

    @MainActor private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
