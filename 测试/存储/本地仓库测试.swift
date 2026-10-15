// 测试边界：在 iOS 内存 SwiftData 容器验证真实快照读写。
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
}
