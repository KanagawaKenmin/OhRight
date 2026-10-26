// 测试边界：验证原始 v1 迁移、权限决策与搜索/历史范围。
// 输入：固定原始 JSON 和领域状态；输出：兼容与偏好断言。
// 不调用系统授权，不读取用户资料。
import Foundation
import XCTest
#if canImport(OhRightCore)
@testable import OhRightCore
#else
@testable import OhRight
#endif

final class ExperienceMigrationTests: XCTestCase {
    func testOriginalV1WorkspaceKeepsUserDataAndDisabledPreference() throws {
        let workspace = try JSONDecoder().decode(Workspace.self, from: LegacyJSON.workspace)
        XCTAssertEqual(workspace.schemaVersion, 2)
        XCTAssertEqual(workspace.revision, 7)
        XCTAssertEqual(workspace.items[0].id.uuidString, "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(workspace.items[0].status, .archived)
        XCTAssertEqual(workspace.items[0].effortMinutes, 17)
        XCTAssertEqual(workspace.items[0].textFormat, .plain)
        XCTAssertEqual(workspace.items[0].entries[0].textFormat, .plain)
        XCTAssertEqual(workspace.items[0].entries[0].previousText, "*保留原文*")
        XCTAssertFalse(workspace.items[0].isStarred)
        XCTAssertTrue(workspace.items[0].attachments.isEmpty)
        XCTAssertEqual(workspace.drafts["capture/idea"]?.textFormat, .plain)
        XCTAssertEqual(workspace.drafts["capture/idea"]?.effortMinutes, 17)
        XCTAssertFalse(workspace.preferences.enabled)
        XCTAssertFalse(workspace.notificationOnboarding.isNewInstallation)
        XCTAssertEqual(try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace)), workspace)
    }

    func testOriginalV1BackupImportsWithoutInventingAttachmentsOrDrafts() throws {
        let package = try CompleteBackup.decode(LegacyJSON.backup)
        XCTAssertEqual(package.manifest.formatVersion, 1)
        XCTAssertTrue(package.files.isEmpty)
        let workspace = BackupCodec.restored(package.manifest, revision: 2)
        XCTAssertEqual(workspace.items[0].textFormat, .plain)
        XCTAssertTrue(workspace.drafts.isEmpty)
        XCTAssertFalse(workspace.preferences.enabled)
    }

    func testNewInstallationGrantedEnablesButDeniedDoesNot() {
        let fresh = Workspace()
        let allowed = NotificationOnboardingRule.completed(fresh, access: .allowed)
        XCTAssertTrue(allowed.preferences.enabled)
        XCTAssertEqual(allowed.preferences.ideaDailyLimit, 1)
        XCTAssertEqual(allowed.preferences.digestMinute, 1230)
        let denied = NotificationOnboardingRule.completed(fresh, access: .denied)
        XCTAssertFalse(denied.preferences.enabled)
        XCTAssertTrue(NotificationOnboardingRule.needsRequest(.notDetermined))
        XCTAssertFalse(NotificationOnboardingRule.needsRequest(.denied))
    }

    func testUpgradeAndExplicitOptOutAreNeverEnabledByPermissionRefresh() throws {
        let old = try JSONDecoder().decode(Workspace.self, from: LegacyJSON.workspace)
        let upgraded = NotificationOnboardingRule.completed(old, access: .allowed)
        XCTAssertFalse(upgraded.preferences.enabled)
        XCTAssertTrue(upgraded.notificationOnboarding.offerEnable)
        var explicit = Workspace()
        explicit.notificationOnboarding.userChoseReminder = true
        let next = NotificationOnboardingRule.completed(explicit, access: .allowed)
        XCTAssertFalse(next.preferences.enabled)
        XCTAssertFalse(next.notificationOnboarding.offerEnable)
        XCTAssertFalse(NotificationOnboardingRule.completed(next, access: .allowed).preferences.enabled)
    }

    func testHistoryOnlyContainsCompletedAndArchivedAndSearchIncludesActive() {
        var active = Samples.idea("进行中的文字")
        active.textFormat = .markdown; active.body = "**可读**关键字"
        var done = Samples.idea("完成"); done.status = .completed
        var archive = Samples.idea("归档"); archive.status = .archived
        var trash = Samples.idea("删除"); trash.status = .deleted
        let all = [active, done, archive, trash]
        XCTAssertEqual(Set(LibraryQuery.results(all, scope: .history).map(\.id)), Set([done.id, archive.id]))
        XCTAssertEqual(LibraryQuery.results(all, scope: .search, query: "可读关键字").map(\.id), [active.id])
        XCTAssertEqual(LibraryQuery.results(all, scope: .trash).map(\.id), [trash.id])
    }

    func testConversionRequiresReopenAndKeepsStarImagesAndCustomEffort() throws {
        var idea = Samples.idea()
        idea.isStarred = true; idea.effortMinutes = 17
        let draft = ItemEditing.draft(for: idea)
        let plan = try ItemEditing.update(idea, draft: draft, kind: .plan, now: Samples.now, timeZone: .gmt)
        XCTAssertEqual(plan.id, idea.id)
        XCTAssertEqual(plan.createdAt, idea.createdAt)
        XCTAssertTrue(plan.isStarred)
        XCTAssertEqual(plan.effortMinutes, 17)
        idea.status = .completed
        XCTAssertThrowsError(try ItemEditing.update(idea, draft: draft, kind: .plan, now: Samples.now, timeZone: .gmt))
        XCTAssertEqual(idea.kind, .idea)
    }

    func testConvertedIdeaDropsOldSnoozeWithoutDroppingOtherItems() {
        let converted = Samples.plan(), other = Samples.idea()
        var workspace = Samples.workspace([converted, other])
        workspace.runtime.invalidatedItemIDs = [converted.id]
        let time = Samples.now.addingTimeInterval(3600)
        let old = ReminderIntent(id: "local/snooze/old", category: .snooze, itemIDs: [converted.id],
            fireAt: time, title: "琐事", body: "旧提醒", sound: false)
        let retained = ReminderIntent(id: "local/snooze/other", category: .snooze, itemIDs: [other.id],
            fireAt: time, title: "另一条", body: "", sound: false)
        let plan = LocalReminderPlanner().makePlan(workspace: workspace, now: Samples.now,
            calendar: Samples.calendar, existing: [old, retained])
        XCTAssertFalse(plan.intents.contains { $0.id == old.id })
        XCTAssertTrue(plan.intents.contains { $0.id == retained.id })
    }
}
