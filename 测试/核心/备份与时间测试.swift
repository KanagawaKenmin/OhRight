// 测试边界：验证备份完整性、损坏拒绝与时区语义。
// 输入：固定日期和 JSON；输出：断言；不写用户文件。
import Foundation
import XCTest
#if canImport(OhRightCore)
@testable import OhRightCore
#else
@testable import OhRight
#endif

final class BackupAndTimeTests: XCTestCase {
    func testBackupRoundTripKeepsContentAndExcludesRuntime() throws {
        var workspace = Samples.workspace([Samples.idea(), Samples.plan()])
        workspace.items[1] = try PlanProgress.addStep(to: workspace.items[1], text: "先打开文档", now: Samples.now)
        workspace.runtime.lastError = "diagnostic-only"
        workspace.drafts["capture/idea"] = CaptureDraft(text: "private-draft")
        let data = try BackupCodec.encode(workspace, now: Samples.now)
        let backup = try BackupCodec.decode(data)
        XCTAssertEqual(backup.items, workspace.items)
        XCTAssertEqual(backup.preferences, workspace.preferences)
        let restored = BackupCodec.restored(backup, revision: 12)
        XCTAssertEqual(restored.revision, 13)
        XCTAssertTrue(restored.runtime.intents.isEmpty)
        XCTAssertEqual(restored.drafts, workspace.drafts)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("diagnostic-only"))
    }

    func testDuplicateIdentityAndInvalidJSONAreRejected() throws {
        let item = Samples.idea()
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(Samples.workspace([item, item]))))
        XCTAssertThrowsError(try BackupCodec.decode(Data("broken".utf8)))
    }

    func testUnknownVersionRejected() throws {
        let data = try BackupCodec.encode(Samples.workspace([]))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["formatVersion"] = 99
        XCTAssertThrowsError(try BackupCodec.decode(JSONSerialization.data(withJSONObject: object)))
    }

    func testDateOnlyBoundaryUsesOriginalZone() {
        let due = Deadline(precision: .dateOnly, value: Samples.now, timeZoneID: "Asia/Tokyo")
        XCTAssertEqual(due.boundary, ISO8601DateFormatter().date(from: "2026-10-15T15:00:00Z"))
    }

    func testDSTDaysUseActualMinutes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        var preferences = ReminderPreferences()
        preferences.timePolicy = .allDay
        let spring = ISO8601DateFormatter().date(from: "2026-03-08T12:00:00Z")!
        let fall = ISO8601DateFormatter().date(from: "2026-11-01T12:00:00Z")!
        for (day, count) in [(spring, 1380), (fall, 1500)] {
            let start = calendar.startOfDay(for: day)
            XCTAssertEqual(TimeSampling.minutes(on: day, after: start.addingTimeInterval(-3600),
                                                 calendar: calendar, preferences: preferences).count, count)
        }
        let clock = TimeSampling.wallClock(minute: 150, on: spring, calendar: calendar)!
        XCTAssertEqual(calendar.component(.hour, from: clock), 3)
    }

    func testSnoozeHonorsQuietHoursAndDailyLimit() throws {
        let item = Samples.idea()
        var workspace = Samples.workspace([item])
        let night = ISO8601DateFormatter().date(from: "2026-10-15T13:30:00Z")! // 当地 22:30
        let original = ReminderIntent(id: "original", category: .idea, itemIDs: [item.id], fireAt: night,
                                       title: "", body: "", sound: false)
        let snooze = try SnoozeReminder.make(from: original, workspace: workspace, now: night, calendar: Samples.calendar)
        XCTAssertEqual(Samples.calendar.component(.hour, from: snooze.fireAt), 9)
        workspace.runtime.snoozeActions = [night, night]
        XCTAssertThrowsError(try SnoozeReminder.make(from: original, workspace: workspace, now: night, calendar: Samples.calendar))
    }
}
