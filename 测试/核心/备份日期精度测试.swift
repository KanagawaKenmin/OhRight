// 测试边界：严格核对小数日期往返、旧毫秒备份及日期编码标记。
// 输入：固定的二进制浮点日期和原始 JSON；输出：逐位相等及兼容断言。
// 不使用容差掩盖完整备份的数据变化，不依赖运行时随机时钟。
import Foundation
import XCTest
#if canImport(OhRightCore)
@testable import OhRightCore
#else
@testable import OhRight
#endif

final class BackupDatePrecisionTests: XCTestCase {
    func testFractionalDatesSurviveExactlyInAllBackupFields() throws {
        let fractions = [814_881_696.1234567, 814_881_696.1234568, 0.123456789, -0.123456789]
        for fraction in fractions {
            let date = Date(timeIntervalSinceReferenceDate: fraction)
            var item = Samples.plan()
            item.createdAt = date; item.updatedAt = date; item.completedAt = date
            item.deletedAt = date; item.mutedUntil = date
            item.deadline = Deadline(precision: .instant, value: date.addingTimeInterval(86400), timeZoneID: "Asia/Tokyo")
            item.deadlineReminderAt = date
            item.entries = [ItemEntry(kind: .progress, text: "日期保留", createdAt: date, editedAt: date)]
            item.steps = [ChecklistStep(text: "一步", isDone: true, completedAt: date)]
            var workspace = Samples.workspace([item])
            workspace.drafts["capture/plan"] = CaptureDraft(text: "草稿", dueDate: date, deadlineReminderAt: date)
            let backup = try BackupCodec.decode(BackupCodec.encode(workspace, now: date))
            XCTAssertEqual(backup.dateEncoding, BackupDateCoding.lossless)
            XCTAssertEqual(backup.exportedAt.timeIntervalSinceReferenceDate.bitPattern, fraction.bitPattern)
            XCTAssertEqual(backup.items, workspace.items)
            XCTAssertEqual(backup.drafts, workspace.drafts)
            XCTAssertEqual(backup.drafts["capture/plan"]?.dueDate.timeIntervalSinceReferenceDate.bitPattern, fraction.bitPattern)
        }
    }

    func testUnmarkedV1AndV2KeepOriginalMillisecondsMeaning() throws {
        for version in [1, 2] {
            var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: LegacyJSON.backup) as? [String: Any])
            raw["formatVersion"] = version
            let draft = try JSONSerialization.jsonObject(with: Data(LegacyJSON.draft.utf8))
            if version == 2 { raw["drafts"] = ["capture/idea": draft] }
            let backup = try BackupCodec.decode(JSONSerialization.data(withJSONObject: raw))
            XCTAssertEqual(backup.dateEncoding, BackupDateCoding.legacy)
            XCTAssertEqual(backup.exportedAt, Date(timeIntervalSince1970: 1_792_026_000))
            XCTAssertEqual(backup.items.first?.createdAt, Date(timeIntervalSince1970: 0))
            if version == 2 { XCTAssertEqual(backup.drafts["capture/idea"]?.dueDate, Date(timeIntervalSince1970: 86.4)) }
        }
    }

    func testUnknownEncodingAndLosslessMarkerOnV1AreRejected() throws {
        for (version, encoding) in [(2, "unknown"), (1, BackupDateCoding.lossless)] {
            var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: LegacyJSON.backup) as? [String: Any])
            raw["formatVersion"] = version; raw["dateEncoding"] = encoding
            XCTAssertThrowsError(try BackupCodec.decode(JSONSerialization.data(withJSONObject: raw)))
        }
    }
}
