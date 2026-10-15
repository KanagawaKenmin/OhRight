// 测试边界：在 iOS 内存与隔离磁盘 SwiftData 容器验证真实快照读写。
// 输入：临时仓库；输出：持久化往返断言；不触碰用户数据库。
import Foundation
import Testing
@testable import OhRight

@MainActor struct LocalRepositoryTests {
    @Test func savesDraftsAndCompleteWorkspace() throws {
        let repository = try LocalWorkspaceRepository(inMemory: true)
        var workspace = try repository.load()
        workspace.drafts["capture/idea"] = CaptureDraft(text: "先留下这半句")
        workspace.items = [Samples.idea(), Samples.plan()]
        workspace.revision = 8
        try repository.save(workspace)
        let restored = try repository.load()
        #expect(restored == workspace)
    }

    @Test func createsMissingParentAndReopensWorkspace() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = root.appendingPathComponent("Nested/Application Support/OhRight.store")
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        var expected = Workspace()
        expected.items = [Samples.idea(), Samples.plan()]
        expected.drafts["capture/idea"] = CaptureDraft(text: "关闭后仍在")
        do {
            let repository = try LocalWorkspaceRepository(storeURL: url)
            try repository.save(expected)
        }
        #expect(FileManager.default.fileExists(atPath: url.path))
        let reopened = try LocalWorkspaceRepository(storeURL: url)
        #expect(try reopened.load() == expected)
    }
}
