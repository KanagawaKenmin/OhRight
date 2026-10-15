// 所属层级：L1 积木层
// 文件职责：编解码有版本的用户备份，验证引用与内容完整性。
// 输入：快照或 JSON；输出：备份与恢复后的纯值。
// 依赖：Foundation、L0；不导出通知运行记录或设备密钥。
import Foundation

struct BackupEnvelope: Codable, Sendable {
    var formatVersion = 1
    var exportedAt: Date
    var items: [Item]
    var preferences: ReminderPreferences
    var appearance: Appearance
}

enum BackupCodec {
    static func encode(_ workspace: Workspace, now: Date = Date()) throws -> Data {
        let backup = BackupEnvelope(exportedAt: now, items: workspace.items,
                                    preferences: workspace.preferences, appearance: workspace.appearance)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(backup)
    }

    static func decode(_ data: Data) throws -> BackupEnvelope {
        guard data.count <= 50_000_000 else { throw DomainError.invalid("备份超过 50 MB，请先检查文件。") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let backup = try decoder.decode(BackupEnvelope.self, from: data)
        guard backup.formatVersion == 1 else { throw DomainError.invalid("暂不支持这个备份版本。") }
        guard backup.items.count <= 50_000 else { throw DomainError.invalid("备份记录数量过多。") }
        try ContentValidation.preferences(backup.preferences)
        var ids = Set<UUID>()
        for item in backup.items {
            try ContentValidation.item(item)
            for id in [item.id] + item.entries.map(\.id) + item.steps.map(\.id) {
                guard ids.insert(id).inserted else { throw DomainError.invalid("备份含有重复编号，未恢复任何资料。") }
            }
        }
        guard Set(backup.preferences.quietIntervals.map(\.id)).count == backup.preferences.quietIntervals.count else {
            throw DomainError.invalid("免打扰区间编号重复。")
        }
        return backup
    }

    static func restored(_ backup: BackupEnvelope, revision: Int) -> Workspace {
        var workspace = Workspace()
        workspace.items = backup.items
        workspace.preferences = backup.preferences
        workspace.appearance = backup.appearance
        workspace.revision = revision + 1
        return workspace
    }

    static func markdown(_ workspace: Workspace) -> String {
        var lines = ["# 哦对了 · 便条导出", ""]
        for item in workspace.items {
            lines += ["## \(item.title)", "", "\(item.kind.label) · \(item.status.label)"]
            if let due = item.deadline { lines.append("截止：\(due.label)（\(due.timeZoneID)）") }
            if !item.body.isEmpty { lines += ["", item.body] }
            if !item.nextAction.isEmpty { lines += ["", "下一步：\(item.nextAction)"] }
            for step in item.steps { lines.append("- [\(step.isDone ? "x" : " ")] \(step.text)") }
            for entry in item.entries {
                lines += ["", "\(entry.createdAt.formatted(.iso8601)) · \(entry.text)"]
                if let previous = entry.previousText { lines.append("上个版本：\(previous)") }
            }
            lines += ["", "---", ""]
        }
        return lines.joined(separator: "\n")
    }
}
