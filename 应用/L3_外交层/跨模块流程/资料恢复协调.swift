// 所属层级：L3 外交层
// 文件职责：校验外部备份，先留安全快照再原子替换资料。
// 输入：用户选择文件/已确认备份；输出：导出数据或恢复结果。
// 依赖：L1 编解码、本地仓库；失败保留原库。
import Foundation

extension AppModel {
    func readBackup(at url: URL) async throws -> BackupPackage {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= StoredZIP.maximumBytes else { throw DomainError.invalid("备份文件超过 250 MB。") }
        return try await Task.detached(priority: .userInitiated) {
            let package = try CompleteBackup.decode(Data(contentsOf: url, options: .mappedIfSafe))
            for reference in CompleteBackup.references(package.manifest) {
                guard let content = package.files[reference.filename] else { throw DomainError.invalid("备份图片缺失。") }
                try PhotoImport.validate(content, attachment: reference)
            }
            return package
        }.value
    }

    func restore(_ package: BackupPackage, safetyRoot: URL? = nil) async throws {
        let backup = package.manifest
        let before = workspace
        let store = attachments
        let manager = FileManager.default
        let root = try safetyRoot ?? manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                   appropriateFor: nil, create: true).appendingPathComponent("SafetyBackups", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let safety = root.appendingPathComponent("before-restore-\(UUID().uuidString).zip")
        let inserted = try await Task.detached(priority: .userInitiated) {
            try CompleteBackup.encode(before, store: store).write(to: safety, options: .atomic)
            return try store.install(package.files)
        }.value
        guard workspace.revision == before.revision, workspace.drafts == before.drafts,
              workspace.appearance == before.appearance else {
            attachments.remove(inserted)
            throw DomainError.invalid("资料在恢复期间已变化，请重新选择备份。")
        }
        var next = BackupCodec.restored(backup, revision: workspace.revision)
        // 系统授权及本机引导选择不从其他设备备份恢复。
        next.notificationOnboarding = workspace.notificationOnboarding
        next.runtime.resetQueue = true
        do { try commit(next, business: false) }
        catch { attachments.remove(inserted); throw error }
        path = []
        undoItem = nil
        notice = "已恢复 \(backup.items.count) 条内容。恢复前资料已保留在本机安全快照。"
    }

    func diagnosticData() throws -> Data {
        struct Report: Encodable {
            let generatedAt: Date
            let revision: Int
            let permission: String
            let mode: String
            let pendingIDs: [String]
            let pendingTimes: [Date]
            let coverageEnd: Date?
            let omittedDeadlines: Int
            let lastError: String?
        }
        let report = Report(generatedAt: Date(), revision: workspace.revision, permission: permissionLabel,
                            mode: preferences.mode.rawValue, pendingIDs: pendingRows.map(\.id),
                            pendingTimes: pendingRows.map(\.fireAt), coverageEnd: workspace.runtime.coverageEnd,
                            omittedDeadlines: workspace.runtime.omittedDeadlines, lastError: diagnosticError ?? workspace.runtime.lastError)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }
}
