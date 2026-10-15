// 测试边界：验证保存校验、历史保留、生命周期与进度语义。
// 输入：固定样本；输出：断言；不访问持久化或系统通知。
import Foundation
import XCTest
#if canImport(OhRightCore)
@testable import OhRightCore
#else
@testable import OhRight
#endif

final class ItemFlowTests: XCTestCase {
    func testSingleSentenceAndOriginalRecord() throws {
        let item = try ItemEditing.create(draft: CaptureDraft(text: "想把阳台弄舒服一点\n先换个灯"), kind: .idea,
                                          now: Samples.now, timeZone: Samples.calendar.timeZone)
        XCTAssertEqual(item.title, "想把阳台弄舒服一点")
        XCTAssertEqual(item.body, "先换个灯")
        XCTAssertEqual(item.entries.count, 1)
        XCTAssertNil(item.deadline)
    }

    func testBlankOrOversizedTitleRejected() {
        XCTAssertThrowsError(try ItemEditing.create(draft: CaptureDraft(text: "  \n"), kind: .idea,
                                                    now: Samples.now, timeZone: .gmt))
        XCTAssertThrowsError(try ItemEditing.create(draft: CaptureDraft(text: String(repeating: "长", count: 121)),
                                                    kind: .idea, now: Samples.now, timeZone: .gmt))
    }

    func testConversionKeepsIdentityAndHistory() throws {
        let idea = try ItemEditing.appendThought(to: Samples.idea(), text: "周末看看植物", now: Samples.now)
        var draft = ItemEditing.draft(for: idea)
        draft.dueDate = Samples.now.addingTimeInterval(86400)
        let plan = try ItemEditing.update(idea, draft: draft, kind: .plan, now: Samples.now, timeZone: .gmt)
        XCTAssertEqual(plan.id, idea.id)
        XCTAssertEqual(plan.entries.first, idea.entries.first)
        XCTAssertEqual(plan.kind, .plan)
        XCTAssertNotNil(plan.deadline)
    }

    func testCompletionIsIdempotentAndReopenPreservesPause() throws {
        let paused = try ItemLifecycle.apply(.pause, to: Samples.plan(), now: Samples.now)
        let complete = try ItemLifecycle.apply(.complete, to: paused, now: Samples.now)
        let duplicate = try ItemLifecycle.apply(.complete, to: complete, now: Samples.now)
        XCTAssertEqual(complete, duplicate)
        XCTAssertEqual(try ItemLifecycle.apply(.reopen, to: complete, now: Samples.now).status, .paused)
    }

    func testDeleteRestorePreservesCompletedState() throws {
        let item = try ItemLifecycle.apply(.complete, to: Samples.idea(), now: Samples.now)
        let deleted = try ItemLifecycle.apply(.delete, to: item, now: Samples.now)
        let restored = try ItemLifecycle.apply(.restore, to: deleted, now: Samples.now)
        XCTAssertEqual(restored.status, .completed)
        XCTAssertEqual(restored.completedAt, item.completedAt)
        XCTAssertNil(restored.deletedAt)
    }

    func testOnlyRealProgressAndCheckedStepsCount() throws {
        var item = Samples.plan()
        let before = item.lastProgressAt
        item = try PlanProgress.addStep(to: item, text: "找资料", now: Samples.now)
        XCTAssertEqual(item.lastProgressAt, before)
        item = try PlanProgress.toggleStep(in: item, stepID: item.steps[0].id, now: Samples.now)
        XCTAssertEqual(item.lastProgressAt, Samples.now)
        XCTAssertEqual(item.status, .active)
        item = try PlanProgress.toggleStep(in: item, stepID: item.steps[0].id, now: Samples.now)
        XCTAssertEqual(item.lastProgressAt, before)
    }

    func testEditedEntryKeepsPreviousTextAndOriginalDate() throws {
        let item = try PlanProgress.append(to: Samples.plan(), text: "完成第一章", now: Samples.now)
        let entry = item.entries[0]
        let edited = try PlanProgress.editEntry(in: item, entryID: entry.id, text: "完成第一节", now: Samples.now.addingTimeInterval(60))
        XCTAssertEqual(edited.entries[0].previousText, entry.text)
        XCTAssertEqual(edited.entries[0].createdAt, entry.createdAt)
    }

    func testCloudUnavailableHasNoFallbackSuccess() {
        XCTAssertFalse(LocalCapabilities().query().cloudAvailable)
        XCTAssertThrowsError(try LocalCapabilities().requestMode(.cloud))
        XCTAssertNoThrow(try LocalCapabilities().requestMode(.local))
    }
}
