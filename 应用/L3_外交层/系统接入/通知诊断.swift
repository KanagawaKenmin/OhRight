// 所属层级：L3 外交层
// 文件职责：只在个人试用中提供可清理的通知检查。
// 输入：用户检查动作；输出：实际系统数量。
// 依赖：UserNotifications；不清除生产提醒、不把回读当送达。
import Foundation
import UserNotifications

extension LocalNotificationDelivery {
    func diagnosticRows() async -> [(id: String, title: String, date: Date?)] {
        await center.pendingNotificationRequests().map {
            (id: $0.identifier, title: $0.content.title, date: ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ??
                ($0.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate())
        }.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    func clearTestNotifications() async {
        let requests = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: requests.filter { $0.identifier.hasPrefix("debug/") }.map(\.identifier))
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.request.identifier.hasPrefix("debug/") }.map { $0.request.identifier })
    }

    func probeCapacity() async throws -> Int {
        let existing = await center.pendingNotificationRequests()
        guard existing.count <= 28 else {
            throw DomainError.invalid("已有提醒较多，为保护现有队列，本次不添加 32 条测试请求。")
        }
        let prefix = "debug/capacity/\(UUID().uuidString)/"
        let ids = (0..<32).map { "\(prefix)\($0)" }
        defer { center.removePendingNotificationRequests(withIdentifiers: ids) }
        for (index, id) in ids.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "排程容量检查"
            content.interruptionLevel = .passive
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(5 * 86400 + index * 60), repeats: false)
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
        let accepted = await center.pendingNotificationRequests()
        return accepted.filter { $0.identifier.hasPrefix(prefix) }.count
    }
}
