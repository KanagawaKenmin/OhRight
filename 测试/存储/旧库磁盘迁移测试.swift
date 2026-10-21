// 测试边界：将 v1 原始 payload 直接写入隔离 SwiftData，迁移后重开。
// 输入：旧版 JSON；输出：原身份/状态/草稿/偏好持久保留断言。
// 不删除或重建真实数据库。
import Foundation
import SwiftData
import Testing
@testable import OhRight

@MainActor struct LegacyDiskMigrationTests {
    @Test func opensOriginalV1PayloadAndReopensSchemaTwo() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = root.appendingPathComponent("Old/OhRight.store")
        defer { try? FileManager.default.removeItem(at: root) }
        var expected: Workspace?
        do {
            let repository = try LocalWorkspaceRepository(storeURL: url)
            let context = ModelContext(repository.container)
            context.autosaveEnabled = false
            context.insert(StoredWorkspace(key: "primary", payload: LegacyJSON.workspace))
            try context.save()
            let migrated = try repository.load()
            #expect(migrated.schemaVersion == 2)
            #expect(!migrated.preferences.enabled)
            #expect(migrated.items[0].status == .archived)
            #expect(migrated.items[0].effortMinutes == 17)
            #expect(migrated.drafts["capture/idea"]?.text == "旧草稿 *原文*")
            try repository.save(migrated)
            expected = migrated
        }
        let reopened = try LocalWorkspaceRepository(storeURL: url)
        #expect(try reopened.load() == expected)
    }
}
