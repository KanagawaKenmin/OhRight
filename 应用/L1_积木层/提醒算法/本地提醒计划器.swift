// 所属层级：L1 积木层
// 文件职责：固定摘要/期限与随机琐事的纯本地排程。
// 输入：快照、日历、实际队列；输出：三日计划与缺口。
// 依赖：L0、同层抽样/摘要；不接触系统通知或存储。
import Foundation

struct LocalReminderPlanner: ReminderPlanner {
    let capacity: Int
    init(capacity: Int = 32) { self.capacity = max(0, capacity) }

    func makePlan(workspace: Workspace, now: Date, calendar: Calendar,
                  existing: [ReminderIntent]) -> SchedulePlan {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 3, to: start)!
        let preferences = workspace.preferences
        guard preferences.enabled, preferences.mode == .local else {
            return SchedulePlan(intents: [], coverageEnd: now, omittedDeadlines: 0)
        }
        let active = workspace.items.filter(\.isRemindable)
        let activeIDs = Set(active.map(\.id))
        var intents = existing.filter { intent in
            intent.category == .snooze && intent.fireAt > now &&
            !workspace.runtime.invalidatedItemIDs.contains(where: { intent.itemIDs.contains($0) }) &&
            intent.itemIDs.allSatisfy { activeIDs.contains($0) } &&
            preferences.allows(intent.fireAt, calendar: calendar)
        }.sorted { $0.fireAt < $1.fireAt }
        intents = Array(intents.prefix(min(4, capacity)))
        intents = intents.compactMap { intent in
            guard let item = active.first(where: { intent.itemIDs == [$0.id] }) else { return nil }
            return make(category: .snooze, id: intent.id, items: [item.id], at: intent.fireAt,
                        title: intent.title, body: item.title, preferences: preferences)
        }
        var omitted = 0
        var limited = false
        for item in active.sorted(by: { ($0.deadlineReminderAt ?? .distantFuture) < ($1.deadlineReminderAt ?? .distantFuture) }) {
            guard item.kind == .plan, let time = item.deadlineReminderAt, time > now else { continue }
            guard time < end, preferences.allows(time, calendar: calendar), intents.count < capacity else {
                omitted += 1
                if time < end && intents.count >= capacity { limited = true }
                continue
            }
            intents.append(make(category: .deadline, id: "local/deadline/\(item.id)", items: [item.id],
                                at: time, title: "哦对了，计划快到期了", body: item.title, preferences: preferences))
        }
        for offset in 0..<3 where preferences.digestEnabled {
            let day = calendar.date(byAdding: .day, value: offset, to: start)!
            guard let time = TimeSampling.wallClock(minute: preferences.digestMinute, on: day, calendar: calendar),
                  time > now, time < end, preferences.allows(time, calendar: calendar) else { continue }
            let plans = PlanSummary.sorted(workspace.items, at: time, calendar: calendar)
            guard !plans.isEmpty else { continue }
            guard intents.count < capacity else { limited = true; continue }
            let id = "local/digest/\(Int(day.timeIntervalSince1970))/\(calendar.timeZone.identifier)"
            intents.append(make(category: .digest, id: id, items: Array(plans.prefix(3).map(\.id)),
                                at: time, title: "哦对了，今天的计划", body: PlanSummary.body(items: plans, at: time, calendar: calendar),
                                preferences: preferences))
        }
        let fixed = intents
        let candidates = active.filter { $0.kind == .idea }
        let retained = retainedIdeas(existing, candidates: candidates, workspace: workspace,
                                     now: now, end: end, calendar: calendar, fixed: fixed)
        for intent in retained {
            if intents.count < capacity { intents.append(intent) } else { limited = true }
        }
        var generator = SeededGenerator(seed: workspace.randomSeed)
        for offset in 0..<3 {
            let day = calendar.date(byAdding: .day, value: offset, to: start)!
            var times = TimeSampling.minutes(on: day, after: now, calendar: calendar, preferences: preferences)
            times.shuffle(using: &generator)
            for time in times {
                let count = intents.filter { $0.category == .idea && calendar.isDate($0.fireAt, inSameDayAs: day) }.count
                if count >= preferences.ideaDailyLimit { break }
                if intents.count >= capacity { limited = true; break }
                guard separated(time, from: intents) else { continue }
                var pool = candidates.filter { eligible($0, at: time, history: workspace.runtime.history + intents) }
                pool.shuffle(using: &generator)
                guard let item = pool.first else { continue }
                let id = "local/idea/\(item.id)/\(Int(time.timeIntervalSince1970))"
                intents.append(make(category: .idea, id: id, items: [item.id], at: time,
                                    title: "哦对了，一个还没想完的念头", body: item.title, preferences: preferences))
            }
        }
        return SchedulePlan(intents: intents.sorted { $0.fireAt < $1.fireAt }, coverageEnd: end,
                            omittedDeadlines: omitted, capacityLimited: limited)
    }

    private func retainedIdeas(_ existing: [ReminderIntent], candidates: [Item], workspace: Workspace,
                               now: Date, end: Date, calendar: Calendar, fixed: [ReminderIntent]) -> [ReminderIntent] {
        var result: [ReminderIntent] = []
        for intent in existing.filter({ $0.category == .idea && $0.fireAt > now && $0.fireAt < end })
            .sorted(by: { $0.fireAt < $1.fireAt }) {
            guard let item = candidates.first(where: { intent.itemIDs == [$0.id] }),
                  !workspace.runtime.invalidatedItemIDs.contains(item.id),
                  workspace.preferences.allows(intent.fireAt, calendar: calendar),
                  eligible(item, at: intent.fireAt, history: workspace.runtime.history + fixed + result),
                  separated(intent.fireAt, from: fixed + result) else { continue }
            let count = result.filter { calendar.isDate($0.fireAt, inSameDayAs: intent.fireAt) }.count
            guard count < workspace.preferences.ideaDailyLimit else { continue }
            result.append(make(category: .idea, id: intent.id, items: [item.id], at: intent.fireAt,
                               title: intent.title, body: item.title, preferences: workspace.preferences))
        }
        return result
    }

    private func eligible(_ item: Item, at date: Date, history: [ReminderIntent]) -> Bool {
        let lastThought = item.entries.filter { [.creation, .thought].contains($0.kind) }
            .map { $0.editedAt ?? $0.createdAt }.max() ?? item.createdAt
        guard date.timeIntervalSince(lastThought) >= 24 * 3600,
              item.mutedUntil.map({ $0 <= date }) ?? true else { return false }
        return !history.contains {
            [.idea, .snooze].contains($0.category) && $0.itemIDs.contains(item.id) &&
            abs($0.fireAt.timeIntervalSince(date)) < 72 * 3600
        }
    }

    private func separated(_ date: Date, from intents: [ReminderIntent]) -> Bool {
        !intents.contains {
            abs($0.fireAt.timeIntervalSince(date)) < ($0.category == .idea ? 7200 : 3600)
        }
    }

    private func make(category: ReminderCategory, id: String, items: [UUID], at: Date,
                       title: String, body: String, preferences: ReminderPreferences) -> ReminderIntent {
        ReminderIntent(id: id, category: category, itemIDs: items, fireAt: at, title: title,
                       body: preferences.contentPreview ? body : "打开哦对了，看看之前记下的内容。", sound: preferences.soundEnabled)
    }
}
