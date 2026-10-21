// 测试边界：为权限、偏好事务和恢复失败提供内存仓库及通知替身。
// 输入：故障标记/回调；输出：实际保存与投递值。
// 不调用 iOS 权限弹窗，不安排系统通知。
import Foundation
@testable import OhRight

@MainActor final class TestWorkspaceRepository: WorkspaceRepository {
    var value: Workspace
    var failSave = false
    init(_ value: Workspace = Workspace()) { self.value = value }
    func load() throws -> Workspace { value }
    func save(_ workspace: Workspace) throws {
        if failSave { throw DomainError.invalid("测试写入失败") }
        value = workspace
    }
}

@MainActor final class TestNotificationService: NotificationService {
    var status: NotificationAccess = .allowed
    var requests = 0
    var queue: [ReminderIntent] = []
    var onReplace: (() -> Void)?
    func configure() {}
    func access() async -> NotificationAccess { status }
    func requestPermission() async throws -> Bool { requests += 1; return status.allowed }
    func pending() async -> [ReminderIntent] { queue }
    func replaceSchedule(_ intents: [ReminderIntent]) async -> DeliveryReport {
        await Task.yield()
        if let action = onReplace { onReplace = nil; action() }
        queue = intents
        return DeliveryReport(accepted: intents, errors: [])
    }
    func pruneDelivered(validItemIDs: Set<UUID>) async {}
    func testNotification(sound: Bool) async throws {}
    func diagnosticRows() async -> [(id: String, title: String, date: Date?)] { [] }
    func clearTestNotifications() async {}
    func probeCapacity() async throws -> Int { 32 }
}
