// 所属层级：L3 外交层
// 文件职责：为通知协调暴露系统适配接口，允许隔离权限/排程测试。
// 输入：授权、测试与队列命令；输出：系统状态和投递结果。
// 依赖：L0；系统对象留在具体适配器内部。
import Foundation

@MainActor protocol NotificationService: ReminderDelivery {
    func configure()
    func access() async -> NotificationAccess
    func requestPermission() async throws -> Bool
    func pruneDelivered(validItemIDs: Set<UUID>) async
    func testNotification(sound: Bool) async throws
    func diagnosticRows() async -> [(id: String, title: String, date: Date?)]
    func clearTestNotifications() async
    func probeCapacity() async throws -> Int
}
