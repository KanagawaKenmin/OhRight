// 测试边界：验证本地通知选择、冷却、保留和容量。
// 输入：可注入时钟和随机种子；输出：行为断言。
// 不用真实等待或系统队列模拟测试通过。
import Foundation
import XCTest
#if canImport(OhRightCore)
@testable import OhRightCore
#else
@testable import OhRight
#endif

final class ReminderRuleTests: XCTestCase {
    private func make(_ workspace: Workspace, existing: [ReminderIntent] = [], now: Date = Samples.now,
                      capacity: Int = 32) -> SchedulePlan {
        LocalReminderPlanner(capacity: capacity).makePlan(workspace: workspace, now: now,
            calendar: Samples.calendar, existing: existing)
    }

    func testSameSeedSameResultAndQuietHoursRespected() {
        let workspace = Samples.workspace((0..<12).map { Samples.idea("念头\($0)") })
        let plan = make(workspace)
        XCTAssertEqual(plan.intents, make(workspace).intents)
        XCTAssertEqual(plan.intents.count, 3)
        for intent in plan.intents {
            XCTAssertTrue(workspace.preferences.allows(intent.fireAt, calendar: Samples.calendar))
            XCTAssertLessThan(intent.fireAt, plan.coverageEnd)
        }
    }

    func testAlreadyScheduledIdeasAreNotReshuffled() {
        let workspace = Samples.workspace((0..<12).map { Samples.idea("念头\($0)") })
        let plan = make(workspace)
        XCTAssertEqual(plan.intents, make(workspace, existing: plan.intents).intents)
    }

    func testNewIdeaWaits24HoursAndSingleIdeaCools72Hours() {
        var item = Samples.idea()
        item.createdAt = Samples.now
        let workspace = Samples.workspace([item])
        let intents = make(workspace).intents
        XCTAssertEqual(intents.count, 1)
        XCTAssertTrue(intents.allSatisfy { $0.fireAt.timeIntervalSince(Samples.now) >= 86400 })
    }

    func testRecentlyPlannedHistoryRemainsInCooldown() {
        let item = Samples.idea()
        var workspace = Samples.workspace([item])
        let prior = Samples.now.addingTimeInterval(-86400)
        workspace.runtime.history = [ReminderIntent(id: "past", category: .idea, itemIDs: [item.id], fireAt: prior,
                                                    title: "", body: "", sound: false)]
        let plan = make(workspace)
        XCTAssertTrue(plan.intents.allSatisfy { $0.fireAt.timeIntervalSince(prior) >= 72 * 3600 })
    }

    func testAllDayQuietMeansNoRequestsWithoutInfiniteLoop() {
        var workspace = Samples.workspace([Samples.idea()])
        workspace.preferences.digestEnabled = false
        workspace.preferences.quietIntervals = [QuietInterval(startMinute: 0, endMinute: 0)]
        XCTAssertTrue(make(workspace).intents.isEmpty)
    }

    func testAllDayPolicyIncludesNightMinutes() {
        var preferences = ReminderPreferences()
        preferences.timePolicy = .allDay
        let day = Samples.calendar.startOfDay(for: Samples.now)
        let times = TimeSampling.minutes(on: day, after: day.addingTimeInterval(-3600), calendar: Samples.calendar, preferences: preferences)
        XCTAssertEqual(times.count, 1440)
        XCTAssertTrue(times.contains { Samples.calendar.component(.hour, from: $0) == 2 })
    }

    func testTwoIdeasAreSeparatedAndDailyLimitHeld() {
        var workspace = Samples.workspace((0..<24).map { Samples.idea("念头\($0)") })
        workspace.preferences.ideaDailyLimit = 2
        let plan = make(workspace)
        XCTAssertEqual(plan.intents.count, 6)
        for pair in zip(plan.intents, plan.intents.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.1.fireAt.timeIntervalSince(pair.0.fireAt), 7200)
        }
    }

    func testNoEmptyDigestAndFutureDigestUsesFutureDate() {
        XCTAssertTrue(make(Samples.workspace([])).intents.isEmpty)
        let workspace = Samples.workspace([Samples.plan(due: Samples.now.addingTimeInterval(86400))])
        let plan = make(workspace)
        XCTAssertEqual(plan.intents.count, 3)
        XCTAssertFalse(plan.intents[0].body.contains("逾期"))
        XCTAssertTrue(plan.intents[2].body.contains("逾期"))
    }

    func testCompletedItemIsRemovedFromExistingQueue() {
        var workspace = Samples.workspace([Samples.idea()])
        let plan = make(workspace)
        workspace.items[0].status = .completed
        XCTAssertTrue(make(workspace, existing: plan.intents).intents.isEmpty)
    }

    func testCapacityReportsOmittedDeadlines() {
        let plans = (0..<10).map { index in
            var item = Samples.plan("计划\(index)")
            item.deadlineReminderAt = Samples.now.addingTimeInterval(3600)
            return item
        }
        let plan = make(Samples.workspace(plans), capacity: 2)
        XCTAssertEqual(plan.intents.count, 2)
        XCTAssertEqual(plan.omittedDeadlines, 8)
        XCTAssertTrue(plan.capacityLimited)
    }

    func testExpiredWindowIsNotBackfilled() {
        let workspace = Samples.workspace((0..<12).map { Samples.idea("念头\($0)") })
        let plan = make(workspace)
        let later = Samples.now.addingTimeInterval(5 * 86400)
        let next = make(workspace, existing: plan.intents, now: later)
        XCTAssertTrue(next.intents.allSatisfy { $0.fireAt > later })
        XCTAssertGreaterThan(next.coverageEnd, plan.coverageEnd)
    }
}
