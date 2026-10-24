// 测试边界：验证含图/草稿/历史/回收站备份、缺图和损坏拒绝。
// 输入：隔离临时目录与固定 PNG；输出：完整往返及文件保护断言。
// 不访问照片库、网络或用户文件。
import Foundation
import XCTest
#if canImport(OhRightCore)
@testable import OhRightCore
#else
@testable import OhRight
#endif

final class AttachmentBackupTests: XCTestCase {
    private var pixel: Data { Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=")! }
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testCompleteBackupRoundTripAcrossFreshStores() throws {
        let first = try AttachmentStore(root: root())
        let image = try first.savePNG(pixel, width: 1, height: 1)
        var item = Samples.idea()
        item.attachments = [image]; item.isStarred = true; item.textFormat = .markdown
        item.entries = [ItemEntry(kind: .thought, text: "新文本", createdAt: Samples.now,
            previousText: "**旧文本**", previousFormat: .markdown, previousAttachments: [image])]
        item = try ItemLifecycle.apply(.delete, to: item, now: Samples.now)
        var workspace = Samples.workspace([item])
        let fractionalDate = Date(timeIntervalSinceReferenceDate: 814_881_696.1234568)
        workspace.drafts["capture/plan"] = CaptureDraft(text: "含图片草稿", dueDate: fractionalDate, attachments: [image])
        let data = try CompleteBackup.encode(workspace, store: first)
        let package = try CompleteBackup.decode(data)
        let second = try AttachmentStore(root: root())
        try second.install(package.files)
        let restored = BackupCodec.restored(package.manifest, revision: 4)
        XCTAssertEqual(restored.items, workspace.items)
        XCTAssertEqual(restored.drafts, workspace.drafts)
        XCTAssertEqual(restored.drafts["capture/plan"]?.dueDate.timeIntervalSinceReferenceDate.bitPattern,
                       fractionalDate.timeIntervalSinceReferenceDate.bitPattern)
        XCTAssertEqual(try second.data(for: image), pixel)
        XCTAssertEqual(restored.items[0].status, .deleted)
        XCTAssertTrue(restored.items[0].isStarred)
    }

    func testMissingCorruptAndPathOnlyBackupsAreRejected() throws {
        let store = try AttachmentStore(root: root())
        let image = try store.savePNG(pixel, width: 1, height: 1)
        var item = Samples.idea(); item.attachments = [image]
        let workspace = Samples.workspace([item])
        let full = try CompleteBackup.encode(workspace, store: store)
        var files = try StoredZIP.decode(full)
        files.removeValue(forKey: "attachments/\(image.filename)")
        XCTAssertThrowsError(try CompleteBackup.decode(StoredZIP.encode(files)))
        files["attachments/\(image.filename)"] = Data("corrupt".utf8)
        XCTAssertThrowsError(try CompleteBackup.decode(StoredZIP.encode(files)))
        XCTAssertThrowsError(try CompleteBackup.decode(BackupCodec.encode(workspace)))
        XCTAssertEqual(try store.data(for: image), pixel)
        try FileManager.default.removeItem(at: store.root.appendingPathComponent(image.filename))
        XCTAssertThrowsError(try CompleteBackup.encode(workspace, store: store))
    }

    func testReferenceCleanupIncludesHistoryDraftAndTrash() throws {
        let store = try AttachmentStore(root: root())
        let retained = try store.savePNG(pixel, width: 1, height: 1)
        let orphan = try store.savePNG(pixel, width: 1, height: 1)
        var item = Samples.idea(); item.status = .deleted
        item.entries = [ItemEntry(kind: .change, text: "修改", createdAt: Samples.now, previousAttachments: [retained])]
        var workspace = Samples.workspace([item])
        workspace.drafts["entry/test"] = CaptureDraft(attachments: [retained])
        try store.collect(referenced: workspace.allAttachments)
        XCTAssertEqual(try store.data(for: retained), pixel)
        XCTAssertThrowsError(try store.data(for: orphan))
        workspace.items = []; workspace.drafts = [:]
        try store.collect(referenced: workspace.allAttachments)
        XCTAssertThrowsError(try store.data(for: retained))
    }

    func testFileConflictDoesNotOverwriteAndInvalidImageCannotBeSaved() throws {
        let store = try AttachmentStore(root: root())
        let image = try store.savePNG(pixel, width: 1, height: 1)
        let other = "\(UUID().uuidString).png"
        XCTAssertThrowsError(try store.install([other: pixel, image.filename: Data("different".utf8)]))
        XCTAssertEqual(try store.data(for: image), pixel)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.root.appendingPathComponent(other).path))
        XCTAssertThrowsError(try store.savePNG(Data(), width: 1, height: 1))
        XCTAssertThrowsError(try store.savePNG(pixel, width: 2, height: 1))
        XCTAssertThrowsError(try store.install(["../outside.png": pixel]))
    }

    func testConversionKeepsAttachmentsAndCancellationHasNoMutation() throws {
        let store = try AttachmentStore(root: root())
        let image = try store.savePNG(pixel, width: 1, height: 1)
        var item = Samples.idea(); item.attachments = [image]
        var draft = ItemEditing.draft(for: item)
        draft.nextAction = "下一步"
        XCTAssertEqual(item.attachments, [image])
        XCTAssertEqual(item.kind, .idea)
        let plan = try ItemEditing.update(item, draft: draft, kind: .plan, now: Samples.now, timeZone: .gmt)
        XCTAssertEqual(plan.attachments, [image])
        XCTAssertEqual(plan.id, item.id)
        XCTAssertEqual(plan.entries.last?.previousAttachments, [image])
    }

    func testReadableZIPIncludesSourceAndImages() throws {
        let store = try AttachmentStore(root: root())
        let image = try store.savePNG(pixel, width: 1, height: 1)
        var item = Samples.idea(); item.attachments = [image]; item.body = "**源文**"
        let files = try StoredZIP.decode(CompleteBackup.encode(Samples.workspace([item]), store: store, readable: true))
        let markdown = String(decoding: try XCTUnwrap(files["便条.md"]), as: UTF8.self)
        XCTAssertTrue(markdown.contains("**源文**"))
        XCTAssertTrue(markdown.contains("attachments/\(image.filename)"))
        XCTAssertEqual(files["attachments/\(image.filename)"], pixel)
    }
}
