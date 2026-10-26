// 测试边界：验证 UI 前置记录严格受开发标记保护，且经过正常业务创建。
// 输入：内存仓库、场景参数；输出：隔离、标题和无效参数断言。
// 不启动 App，不调用系统通知，不写正式资料。
import Foundation
import Testing
@testable import OhRight

@MainActor struct UITestScenarioTests {
    @Test func fixturesCreateValidatedIdeasOnlyInExplicitUITestMode() throws {
        let store = try AttachmentStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: store.root) }
        for (name, title) in [("quick-actions", "需要处理的琐事"), ("conversion", "从琐事开始"), ("library", "只在搜索里出现")] {
            let model = try AppModel(repository: TestWorkspaceRepository(), delivery: TestNotificationService(), attachmentStore: store)
            try UITestScenario.prepare(model, arguments: ["--uitest-fixture=\(name)"])
            #expect(model.workspace.items.isEmpty)
            try UITestScenario.prepare(model, arguments: ["--uitest", "--uitest-fixture=\(name)"])
            #expect(model.workspace.items.count == 1)
            let item = try #require(model.workspace.items.first)
            #expect(item.title == title && item.kind == .idea && item.status == .active)
            #expect(!item.entries.isEmpty)
            #expect(throws: (any Error).self) {
                try UITestScenario.prepare(model, arguments: ["--uitest", "--uitest-fixture=\(name)"])
            }
        }
    }

    @Test func emptyCaptureScenarioStaysEmptyAndUnknownFixtureFails() throws {
        let store = try AttachmentStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: store.root) }
        let model = try AppModel(repository: TestWorkspaceRepository(), delivery: TestNotificationService(), attachmentStore: store)
        try UITestScenario.prepare(model, arguments: ["--uitest"])
        #expect(model.workspace.items.isEmpty)
        #expect(throws: (any Error).self) {
            try UITestScenario.prepare(model, arguments: ["--uitest", "--uitest-fixture=unknown"])
        }
        #expect(model.workspace.items.isEmpty)
    }
}
