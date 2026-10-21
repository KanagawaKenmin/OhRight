// 所属层级：L1 积木层
// 文件职责：编解码有版本的用户备份，验证引用与内容完整性。
// 输入：快照或 JSON；输出：备份与恢复后的纯值。
// 依赖：Foundation、L0；不导出通知运行记录或设备密钥。
import Foundation

struct BackupEnvelope: Codable, Sendable {
    var formatVersion = 2
    var exportedAt: Date
    var items: [Item]
    var preferences: ReminderPreferences
    var appearance: Appearance
    var drafts: [String: CaptureDraft] = [:]
    var attachmentHashes: [String: String] = [:]
}

enum BackupCodec {
    static func encode(_ workspace: Workspace, now: Date = Date(), hashes: [String: String] = [:]) throws -> Data {
        let backup = BackupEnvelope(exportedAt: now, items: workspace.items,
                                    preferences: workspace.preferences, appearance: workspace.appearance,
                                    drafts: workspace.drafts, attachmentHashes: hashes)
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
        guard (1...2).contains(backup.formatVersion) else { throw DomainError.invalid("暂不支持这个备份版本。") }
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
        try ContentValidation.date(backup.exportedAt)
        for draft in backup.drafts.values {
            guard draft.text.count <= 20_000, draft.nextAction.count <= 20_000,
                  draft.attachments.count <= Attachment.maximumPerItem else { throw DomainError.invalid("备份草稿无效。") }
            try ContentValidation.date(draft.dueDate)
            try ContentValidation.attachmentGroup(draft.attachments)
            if let reminder = draft.deadlineReminderAt { try ContentValidation.date(reminder) }
            if let effort = draft.effortMinutes, !(1...1440).contains(effort) { throw DomainError.invalid("草稿耗时无效。") }
        }
        return backup
    }

    static func restored(_ backup: BackupEnvelope, revision: Int) -> Workspace {
        var workspace = Workspace()
        workspace.items = backup.items
        workspace.preferences = backup.preferences
        workspace.appearance = backup.appearance
        workspace.drafts = backup.drafts
        workspace.revision = revision + 1
        return workspace
    }

    static func markdown(_ workspace: Workspace) -> String {
        var lines = ["# 哦对了 · 便条导出", ""]
        for item in workspace.items {
            lines += ["## \(item.title)", "", "\(item.kind.label) · \(item.status.label)"]
            if let due = item.deadline { lines.append("截止：\(due.label)（\(due.timeZoneID)）") }
            if !item.body.isEmpty { lines += ["", item.body] }
            for attachment in item.attachments { lines += ["", "![图片](attachments/\(attachment.filename))"] }
            if !item.nextAction.isEmpty { lines += ["", "下一步：\(item.nextAction)"] }
            for step in item.steps { lines.append("- [\(step.isDone ? "x" : " ")] \(step.text)") }
            for entry in item.entries {
                lines += ["", "\(entry.createdAt.formatted(.iso8601)) · \(entry.text)"]
                if let previous = entry.previousText { lines.append("上个版本：\(previous)") }
                for attachment in entry.attachments { lines += ["", "![图片](attachments/\(attachment.filename))"] }
                for attachment in entry.previousAttachments { lines += ["", "![上个版本图片](attachments/\(attachment.filename))"] }
            }
            lines += ["", "---", ""]
        }
        for (key, draft) in workspace.drafts.sorted(by: { $0.key < $1.key }) {
            lines += ["## 草稿 · \(key)", "", draft.text, "", draft.nextAction]
            for attachment in draft.attachments { lines += ["", "![草稿图片](attachments/\(attachment.filename))"] }
        }
        return lines.joined(separator: "\n")
    }
}

extension BackupEnvelope {
    private enum CodingKeys: String, CodingKey {
        case formatVersion, exportedAt, items, preferences, appearance, drafts, attachmentHashes
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decode(Int.self, forKey: .formatVersion)
        exportedAt = try c.decode(Date.self, forKey: .exportedAt)
        items = try c.decode([Item].self, forKey: .items)
        preferences = try c.decode(ReminderPreferences.self, forKey: .preferences)
        appearance = try c.decode(Appearance.self, forKey: .appearance)
        drafts = try c.decodeIfPresent([String: CaptureDraft].self, forKey: .drafts) ?? [:]
        attachmentHashes = try c.decodeIfPresent([String: String].self, forKey: .attachmentHashes) ?? [:]
    }
}
