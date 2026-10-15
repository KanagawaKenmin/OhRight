// 所属层级：L3 外交层
// 文件职责：校验外部备份，先留安全快照再原子替换资料。
// 输入：用户选择文件/已确认备份；输出：导出数据或恢复结果。
// 依赖：L1 编解码、本地仓库；失败保留原库。
import Foundation

extension AppModel {
    func readBackup(at url: URL) throws -> BackupEnvelope {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 50_000_000 else { throw DomainError.invalid("备份文件超过 50 MB。") }
        return try BackupCodec.decode(Data(contentsOf: url))
    }

    func restore(_ backup: BackupEnvelope) throws {
        let manager = FileManager.default
        let root = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                   appropriateFor: nil, create: true).appendingPathComponent("SafetyBackups", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let safety = root.appendingPathComponent("before-restore-\(UUID().uuidString).json")
        try BackupCodec.encode(workspace).write(to: safety, options: .atomic)
        var next = BackupCodec.restored(backup, revision: workspace.revision)
        next.runtime.resetQueue = true
        try commit(next, business: false)
        path = []
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
                            omittedDeadlines: workspace.runtime.omittedDeadlines, lastError: workspace.runtime.lastError)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }
}
