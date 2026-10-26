// 测试边界：在隔离文件夹验证保存失败回滚、并行重排与恢复保护。
// 输入：故障仓库、通知替身；输出：最终快照及文件断言。
// 不访问真实 SwiftData、系统通知或正式附件目录。
import Foundation
import Testing
@testable import OhRight

@MainActor struct SettingsAndRestoreTests {
    private func isolatedStore() throws -> AttachmentStore {
        try AttachmentStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    @Test func immediateSettingsPreserveSequentialChangesAndRollbackFailure() throws {
        let repository = TestWorkspaceRepository()
        let store = try isolatedStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let model = try AppModel(repository: repository, delivery: TestNotificationService(), attachmentStore: store)
        var first = model.preferences; first.ideaDailyLimit = 2
        try model.savePreferences(first)
        var second = model.preferences; second.digestEnabled = false
        try model.savePreferences(second)
        #expect(repository.value.preferences.ideaDailyLimit == 2)
        #expect(!repository.value.preferences.digestEnabled)
        #expect(!repository.value.notificationOnboarding.userChoseReminder)
        let before = model.workspace
        repository.failSave = true
        var failing = model.preferences; failing.contentPreview = false
        #expect(throws: (any Error).self) { try model.savePreferences(failing) }
        #expect(model.workspace == before)
        #expect(repository.value == before)
    }

    @Test func quietConflictPreservesSettingsIncludingWhenPaused() throws {
        let repository = TestWorkspaceRepository()
        let store = try isolatedStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let model = try AppModel(repository: repository, delivery: TestNotificationService(), attachmentStore: store)
        var changed = model.preferences
        changed.quietIntervals = [QuietInterval(startMinute: 1200, endMinute: 540)]
        #expect(throws: (any Error).self) { try model.savePreferences(changed) }
        #expect(model.preferences == repository.value.preferences)
        #expect(model.preferences.quietIntervals[0].startMinute == 1380)
    }

    @Test func permissionRequestAndSystemRefreshDoNotEnablePausedReminders() async throws {
        let repository = TestWorkspaceRepository()
        let store = try isolatedStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let service = TestNotificationService()
        let model = try AppModel(repository: repository, delivery: service, attachmentStore: store)
        await model.requestNotificationAccess()
        #expect(service.requests == 1)
        #expect(!model.preferences.enabled)
        #expect(model.notificationAccess.allowed)
        #expect(service.queue.isEmpty)
    }

    @Test func changedRevisionDuringDeliveryReplansWithLatestPreferences() async throws {
        let repository = TestWorkspaceRepository(Samples.workspace([Samples.plan(due: Date().addingTimeInterval(86400))]))
        let store = try isolatedStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let service = TestNotificationService()
        let model = try AppModel(repository: repository, delivery: service, attachmentStore: store)
        service.onReplace = {
            var next = model.preferences; next.enabled = false
            model.attempt { try model.savePreferences(next) }
        }
        await model.refreshNotifications()
        #expect(!model.preferences.enabled)
        #expect(service.queue.isEmpty)
        #expect(model.pendingRows.isEmpty)
        #expect(model.workspace.runtime.appliedRevision == model.workspace.revision)
    }

    @Test func restoreSaveFailureKeepsOldDatabaseAndRemovesNewFiles() async throws {
        let pixel = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=")!
        let source = try isolatedStore(), target = try isolatedStore()
        let safety = target.root.appendingPathComponent("Safety")
        defer { try? FileManager.default.removeItem(at: source.root); try? FileManager.default.removeItem(at: target.root) }
        let reference = try source.savePNG(pixel, width: 1, height: 1)
        var incoming = Samples.idea("导入的内容"); incoming.attachments = [reference]
        let package = try CompleteBackup.decode(CompleteBackup.encode(Samples.workspace([incoming]), store: source))
        let original = Samples.workspace([Samples.idea("当前内容")])
        let repository = TestWorkspaceRepository(original)
        let model = try AppModel(repository: repository, delivery: TestNotificationService(), attachmentStore: target)
        repository.failSave = true
        do { try await model.restore(package, safetyRoot: safety); Issue.record("写入失败时不应恢复成功") } catch {}
        #expect(model.workspace == original)
        #expect(repository.value == original)
        #expect(!FileManager.default.fileExists(atPath: target.root.appendingPathComponent(reference.filename).path))
        let snapshots = try FileManager.default.contentsOfDirectory(at: safety, includingPropertiesForKeys: nil)
        #expect(snapshots.count == 1)
        let old = try CompleteBackup.decode(Data(contentsOf: snapshots[0]))
        #expect(old.manifest.items == original.items)
    }

    @Test func archiveAndDeleteUndoPreserveExactContent() throws {
        let original = Samples.idea()
        let repository = TestWorkspaceRepository(Samples.workspace([original]))
        let store = try isolatedStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let model = try AppModel(repository: repository, delivery: TestNotificationService(), attachmentStore: store)
        try model.quickAction(original.id, action: .archive)
        #expect(model.item(original.id)?.status == .archived)
        model.undoQuickAction()
        #expect(model.item(original.id) == original)
        try model.quickAction(original.id, action: .delete)
        try model.toggleStar(original.id)
        model.undoQuickAction()
        #expect(model.item(original.id)?.status == .deleted)
        #expect(model.message != nil)
    }
}
