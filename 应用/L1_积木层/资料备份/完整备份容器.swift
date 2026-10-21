// 所属层级：L1 积木层
// 文件职责：构建/校验 manifest 与图片 ZIP，兼容无图 v1 JSON。
// 输入：快照、图片字节或备份；输出：已全部校验的恢复值。
// 依赖：受限 ZIP、备份编解码、附件仓库；不切换用户数据库。
import Foundation

struct BackupPackage: Sendable {
    var manifest: BackupEnvelope
    var files: [String: Data]
}

enum CompleteBackup {
    static func encode(_ workspace: Workspace, store: AttachmentStore, readable: Bool = false) throws -> Data {
        var files: [String: Data] = [:], hashes: [String: String] = [:]
        var references: [String: Attachment] = [:]
        for attachment in workspace.allAttachments {
            try attachment.validate()
            if let old = references[attachment.filename], old != attachment { throw DomainError.invalid("同编号图片的信息不一致。") }
            references[attachment.filename] = attachment
        }
        guard references.count < StoredZIP.maximumFiles,
              references.values.reduce(0, { $0 + $1.byteCount }) < StoredZIP.maximumBytes else {
            throw DomainError.invalid("完整备份超过 250 MB 或图片数量过多，请先减少资料量。")
        }
        for attachment in references.values {
            let content = try store.data(for: attachment)
            files["attachments/\(attachment.filename)"] = content
            hashes[attachment.filename] = FileDigest.sha256(content)
        }
        if readable { files["便条.md"] = Data(BackupCodec.markdown(workspace).utf8) }
        else {
            let manifest = try BackupCodec.encode(workspace, hashes: hashes)
            guard manifest.count <= 50_000_000 else { throw DomainError.invalid("备份清单超过 50 MB。") }
            files["manifest.json"] = manifest
        }
        return try StoredZIP.encode(files)
    }

    static func decode(_ data: Data) throws -> BackupPackage {
        if data.prefix(2) != Data([0x50, 0x4b]) {
            let manifest = try BackupCodec.decode(data)
            guard references(manifest).isEmpty, manifest.attachmentHashes.isEmpty else {
                throw DomainError.invalid("此 JSON 只有图片路径，缺少图片文件。请选择完整 ZIP 备份。")
            }
            return BackupPackage(manifest: manifest, files: [:])
        }
        let contents = try StoredZIP.decode(data)
        guard let json = contents["manifest.json"] else { throw DomainError.invalid("备份缺少 manifest.json。") }
        let manifest = try BackupCodec.decode(json)
        guard manifest.formatVersion == 2 else { throw DomainError.invalid("图片备份版本无法识别。") }
        var referencesByName: [String: Attachment] = [:], ids: [UUID: Attachment] = [:]
        for attachment in references(manifest) {
            try attachment.validate()
            if let old = ids[attachment.id], old != attachment { throw DomainError.invalid("同编号图片的信息不一致。") }
            ids[attachment.id] = attachment
            referencesByName[attachment.filename] = attachment
        }
        guard Set(contents.keys) == Set(["manifest.json"] + referencesByName.keys.map { "attachments/\($0)" }),
              Set(manifest.attachmentHashes.keys) == Set(referencesByName.keys) else {
            throw DomainError.invalid("备份清单与图片文件不一致，未替换任何资料。")
        }
        var files: [String: Data] = [:]
        for (name, attachment) in referencesByName {
            guard let content = contents["attachments/\(name)"],
                  FileDigest.sha256(content) == manifest.attachmentHashes[name] else {
                throw DomainError.invalid("备份图片缺失或校验不通过，未替换任何资料。")
            }
            try AttachmentStore.validatePNG(content, attachment: attachment)
            files[name] = content
        }
        return BackupPackage(manifest: manifest, files: files)
    }

    static func references(_ manifest: BackupEnvelope) -> [Attachment] {
        manifest.items.flatMap(\.allAttachments) + manifest.drafts.values.flatMap(\.attachments)
    }
}
