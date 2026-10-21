// 测试边界：检验 manifest/哈希均正确但像素损坏的备份，以及本机授权标记。
// 输入：隔离文件及通知替身；输出：恢复前拒绝/成功后标记保留断言。
// 不访问用户附件或真实通知权限。
import Foundation
import Testing
@testable import OhRight

@MainActor struct ImageRestoreValidationTests {
    @Test func rejectsUndecodableImageBeforeChangingCurrentWorkspace() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = try AttachmentStore(root: root.appendingPathComponent("Source"))
        let target = try AttachmentStore(root: root.appendingPathComponent("Target"))
        defer { try? FileManager.default.removeItem(at: root) }
        let full = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=")!
        let broken = try source.savePNG(Data(full.prefix(24)), width: 1, height: 1)
        var incoming = Samples.idea(); incoming.attachments = [broken]
        let url = root.appendingPathComponent("broken.zip")
        try CompleteBackup.encode(Samples.workspace([incoming]), store: source).write(to: url)
        let original = Samples.workspace([Samples.idea("当前资料")])
        let repository = TestWorkspaceRepository(original)
        let model = try AppModel(repository: repository, delivery: TestNotificationService(), attachmentStore: target)
        do { _ = try await model.readBackup(at: url); Issue.record("缺少像素数据的图片不能通过恢复预检") } catch {}
        #expect(model.workspace == original)
        #expect(repository.value == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.root.path).isEmpty)
    }

    @Test func successfulRestoreKeepsDeviceOnboardingButRestoresBackupPreferences() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try AttachmentStore(root: root.appendingPathComponent("Images"))
        defer { try? FileManager.default.removeItem(at: root) }
        var original = Workspace()
        original.notificationOnboarding = NotificationOnboarding(version: 1, isNewInstallation: false, userChoseReminder: true)
        let repository = TestWorkspaceRepository(original)
        let service = TestNotificationService(); service.status = .denied
        let model = try AppModel(repository: repository, delivery: service, attachmentStore: store)
        var incoming = Samples.workspace([Samples.idea("完整恢复")])
        incoming.drafts["capture/idea"] = CaptureDraft(text: "也要恢复的草稿")
        let package = try CompleteBackup.decode(CompleteBackup.encode(incoming, store: store))
        try await model.restore(package, safetyRoot: root.appendingPathComponent("Safety"))
        #expect(model.workspace.items == incoming.items)
        #expect(model.workspace.drafts == incoming.drafts)
        #expect(model.workspace.notificationOnboarding == original.notificationOnboarding)
        #expect(model.preferences.enabled)
        await model.refreshNotifications()
        #expect(model.notificationAccess == .denied)
        #expect(service.queue.isEmpty)
    }
}
