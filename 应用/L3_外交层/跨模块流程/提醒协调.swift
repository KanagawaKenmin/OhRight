// 所属层级：L3 外交层
// 文件职责：串行协调本地资料版本、权限和通知队列。
// 输入：启动/资料变化/通知操作；输出：真实投递报告。
// 依赖：L1 计划器、L2 稍后流程、系统适配；无后台常驻。
import Foundation
import UserNotifications

extension AppModel {
    func refreshNotifications() async {
        guard !isRefreshing else { refreshAgain = true; return }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshAgain = false
            let access = await delivery.access()
            permissionLabel = access.label
            notificationAccess = access
            let actual = await delivery.pending()
            let now = Date()
            var source = workspace
            let revision = source.revision
            let past = source.runtime.history + source.runtime.intents.filter { $0.fireAt <= now }
            let recent = past.filter { now.timeIntervalSince($0.fireAt) <= 4 * 24 * 3600 }
            source.runtime.history = Array(Dictionary(recent.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values)
            source.runtime.handledActions = source.runtime.handledActions.filter { now.timeIntervalSince($0.value) < 7 * 24 * 3600 }
            source.runtime.snoozeActions.removeAll { now.timeIntervalSince($0) > 2 * 24 * 3600 }
            let activeIDs = Set(source.items.filter(\.isRemindable).map(\.id))
            source.runtime.requestedSnoozes.removeAll { intent in
                intent.fireAt <= now || !intent.itemIDs.allSatisfy { activeIDs.contains($0) }
            }
            var existing = source.runtime.resetQueue ? [] : actual
            for intent in source.runtime.requestedSnoozes {
                existing.removeAll { $0.id == intent.id }
                existing.append(intent)
            }
            if source.runtime.timeZoneID != calendar.timeZone.identifier {
                existing.removeAll { $0.category == .idea }
            }
            var plan = planner.makePlan(workspace: source, now: now, calendar: calendar, existing: existing)
            if !access.allowed { plan.intents = [] }
            let result = await delivery.replaceSchedule(plan.intents)
            await delivery.pruneDelivered(validItemIDs: source.preferences.enabled ? activeIDs : [])
            guard workspace.revision == revision else { refreshAgain = true; continue }
            var next = workspace
            next.runtime.history = source.runtime.history
            next.runtime.handledActions = source.runtime.handledActions
            next.runtime.snoozeActions = source.runtime.snoozeActions
            next.runtime.intents = result.accepted
            let acceptedIDs = Set(result.accepted.map(\.id))
            next.runtime.requestedSnoozes = source.runtime.requestedSnoozes.filter { !acceptedIDs.contains($0.id) }
            next.runtime.coverageEnd = access.allowed && preferences.enabled ? plan.coverageEnd : nil
            next.runtime.omittedDeadlines = plan.omittedDeadlines
            next.runtime.capacityLimited = plan.capacityLimited
            next.runtime.appliedRevision = result.errors.isEmpty && access.allowed ? revision : -1
            next.runtime.timeZoneID = calendar.timeZone.identifier
            next.runtime.lastPreferences = preferences
            next.runtime.resetQueue = false
            next.runtime.invalidatedItemIDs = result.errors.isEmpty ? [] : source.runtime.invalidatedItemIDs
            next.runtime.lastError = result.errors.isEmpty ? nil : result.errors.joined(separator: "\n")
            pendingRows = result.accepted.sorted { $0.fireAt < $1.fireAt }
            attempt { try commit(next, business: false, refresh: false) }
        } while refreshAgain
    }

    func requestNotificationAccess() async {
        do {
            let allowed = try await delivery.requestPermission()
            await refreshNotifications()
            if !allowed {
                message = "通知尚未允许，记录功能仍可使用。可以到系统设置开启。"
            }
        } catch { report(error) }
    }

    func handle(_ event: NotificationEvent) async {
        guard let intent = event.intent else { notice = "欢迎回来，看看之前记下的内容。"; return }
        let key = "\(intent.id)|\(event.action)|\(intent.fireAt.timeIntervalSince1970)"
        if event.action == "snooze" {
            guard workspace.runtime.handledActions[key] == nil else { return }
            do {
                let snooze = try SnoozeReminder.make(from: intent, workspace: workspace, now: Date(), calendar: calendar)
                var next = workspace
                next.runtime.requestedSnoozes.removeAll { $0.id == snooze.id }
                next.runtime.requestedSnoozes.append(snooze)
                next.runtime.handledActions[key] = Date()
                next.runtime.snoozeActions.append(Date())
                try commit(next, refresh: false)
                await refreshNotifications()
                notice = "已安排稍后提醒：\(snooze.fireAt.formatted(date: .abbreviated, time: .shortened))"
            } catch { report(error) }
        } else if intent.category == .digest {
            routeGeneration += 1
            selectMode(.plan)
            path = []
        } else if let id = intent.itemIDs.first, let current = item(id), current.status != .deleted {
            routeGeneration += 1
            selectMode(current.kind)
            path = [id]
        } else {
            notice = "这条内容已删除，可以继续看看其他便条。"
        }
    }
}
