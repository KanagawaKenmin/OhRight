// 所属层级：L3 外交层
// 文件职责：适配 iOS 本地通知，差量更新与真实队列回读。
// 输入：ReminderIntent；输出：实际接受列表和错误明细。
// 依赖：UserNotifications、L0；不处理事项业务状态转换。
import Foundation
import UserNotifications

@MainActor final class LocalNotificationDelivery: ReminderDelivery {
    let center = UNUserNotificationCenter.current()

    func configure() {
        let open = UNNotificationAction(identifier: "open", title: "打开", options: [.foreground])
        let snooze = UNNotificationAction(identifier: "snooze", title: "稍后提醒", options: [.authenticationRequired])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "item", actions: [snooze, open], intentIdentifiers: []),
            UNNotificationCategory(identifier: "digest", actions: [open], intentIdentifiers: [])
        ])
    }

    func access() async -> (allowed: Bool, label: String) {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized: return (true, settings.alertSetting == .enabled ? "已允许" : "已允许，横幅由系统设置控制")
        case .provisional: return (true, "临时允许，仅安静投递")
        case .ephemeral: return (true, "暂时允许")
        case .denied: return (false, "未允许，请到系统设置开启")
        case .notDetermined: return (false, "尚未请求")
        @unknown default: return (false, "未知权限状态")
        }
    }

    func requestPermission() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func pending() async -> [ReminderIntent] {
        let requests = await center.pendingNotificationRequests()
        return requests.filter { $0.identifier.hasPrefix("local/") }.compactMap(Self.intent)
    }

    func replaceSchedule(_ intents: [ReminderIntent]) async -> DeliveryReport {
        let existing = await center.pendingNotificationRequests()
        let desired = Dictionary(uniqueKeysWithValues: intents.map { ($0.id, $0) })
        let stale = existing.filter { $0.identifier.hasPrefix("local/") && desired[$0.identifier] == nil }
        center.removePendingNotificationRequests(withIdentifiers: stale.map(\.identifier))
        var errors: [String] = []
        for intent in intents {
            let old = existing.first { $0.identifier == intent.id }
            if old?.content.userInfo["fingerprint"] as? String == intent.fingerprint { continue }
            do { try await center.add(try request(for: intent)) }
            catch { errors.append("\(intent.id): \(error.localizedDescription)") }
        }
        let actual = await pending()
        let accepted = intents.filter { intent in actual.contains { $0.id == intent.id && $0.fingerprint == intent.fingerprint } }
        if accepted.count != intents.count { errors.append("部分请求尚未被系统接受，打开应用时会重试。") }
        if actual.contains(where: { desired[$0.id] == nil }) { errors.append("仍有待移除的旧请求，打开应用时会再次检查。") }
        return DeliveryReport(accepted: accepted, errors: errors)
    }

    func pruneDelivered(validItemIDs: Set<UUID>) async {
        let delivered = await center.deliveredNotifications()
        let invalid = delivered.filter {
            guard $0.request.identifier.hasPrefix("local/"), let intent = Self.intent($0.request) else { return false }
            return !intent.itemIDs.allSatisfy { validItemIDs.contains($0) }
        }
        center.removeDeliveredNotifications(withIdentifiers: invalid.map { $0.request.identifier })
    }

    func testNotification() async throws {
        let content = UNMutableNotificationContent()
        content.title = "哦对了，测试提醒到了"
        content.body = "这条通知由 iPhone 本地安排。打开应用查看你的便条。"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 120, repeats: false)
        center.removePendingNotificationRequests(withIdentifiers: ["debug/two-minutes"])
        try await center.add(UNNotificationRequest(identifier: "debug/two-minutes", content: content, trigger: trigger))
    }

    private func request(for intent: ReminderIntent) throws -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = intent.title
        content.body = intent.body
        content.sound = intent.sound ? .default : nil
        content.interruptionLevel = .active
        content.categoryIdentifier = intent.category == .digest ? "digest" : "item"
        content.threadIdentifier = intent.category == .digest ? "plans" : intent.itemIDs.first?.uuidString ?? "ideas"
        content.userInfo = ["intent": try JSONEncoder().encode(intent).base64EncodedString(), "fingerprint": intent.fingerprint]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: intent.fireAt)
        components.timeZone = .gmt
        return UNNotificationRequest(identifier: intent.id, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    }

    nonisolated static func intent(_ request: UNNotificationRequest) -> ReminderIntent? {
        guard let encoded = request.content.userInfo["intent"] as? String,
              let data = Data(base64Encoded: encoded) else { return nil }
        return try? JSONDecoder().decode(ReminderIntent.self, from: data)
    }
}
