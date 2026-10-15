// 所属层级：L3 外交层
// 文件职责：将系统回调转为可发送值，冷启动时缓存路由。
// 输入：系统通知；输出：主线程领域操作。
// 依赖：UserNotifications、应用状态；不跨线程传送系统响应对象。
import Foundation
import UserNotifications

struct NotificationEvent: Sendable {
    var requestID: String
    var action: String
    var intent: ReminderIntent?
}

@MainActor final class NotificationRouter {
    static let shared = NotificationRouter()
    private(set) var model: AppModel?
    private var waiting: [NotificationEvent] = []

    /// 通知后台回调与界面复用同一仓库，不能依赖 Window.task 才能处理稍后操作。
    func resolveModel(inMemory: Bool = false) throws -> AppModel {
        if let model { return model }
        let repository = try LocalWorkspaceRepository(inMemory: inMemory)
        let delivery = LocalNotificationDelivery()
        delivery.configure()
        let value = try AppModel(repository: repository, delivery: delivery)
        model = value
        return value
    }

    func attach(_ model: AppModel) async {
        self.model = model
        let events = waiting
        waiting.removeAll()
        for event in events { await model.handle(event) }
    }

    func receive(_ event: NotificationEvent) async {
        do {
            let model = try resolveModel()
            await model.handle(event)
        } catch {
            // 仓库不可用时不假装已保存；在同次启动恢复后重试。
            waiting.append(event)
        }
    }
}

final class NotificationBridge: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationBridge()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let event = NotificationEvent(requestID: response.notification.request.identifier,
                                      action: response.actionIdentifier,
                                      intent: LocalNotificationDelivery.intent(response.notification.request))
        await NotificationRouter.shared.receive(event)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let intent = LocalNotificationDelivery.intent(notification.request)
        let suppress = await MainActor.run {
            guard let intent, let model = NotificationRouter.shared.model else { return false }
            return model.readingItemID.map { intent.itemIDs.contains($0) } ?? false
        }
        return suppress ? [] : [.banner, .list]
    }
}
