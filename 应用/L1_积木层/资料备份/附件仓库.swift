// 所属层级：L1 积木层
// 文件职责：图片原件的原子落盘、受限读取与引用清理。
// 输入：已处理 PNG、附件引用；输出：稳定文件或明确错误。
// 依赖：Foundation、L0；不保存 SwiftData，不申请照片权限。
import Foundation

struct AttachmentStore: Sendable {
    let root: URL
    init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func data(for attachment: Attachment) throws -> Data {
        try attachment.validate()
        let url = root.appendingPathComponent(attachment.filename)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard size == attachment.byteCount else { throw DomainError.invalid("图片缺失或损坏，请保留原资料并检查备份。") }
        let data = try Data(contentsOf: url)
        try Self.validatePNG(data, attachment: attachment)
        return data
    }

    /// 先写临时文件再原子移动；元数据提交失败留下的孤立文件由下次扫描回收。
    func savePNG(_ data: Data, width: Int, height: Int) throws -> Attachment {
        let id = UUID()
        let attachment = Attachment(id: id, filename: "\(id.uuidString).png", width: width, height: height, byteCount: data.count)
        try Self.validatePNG(data, attachment: attachment)
        _ = try install([attachment.filename: data])
        return attachment
    }

    /// 同名内容冲突必须失败；失败撤销本次新写入文件，原文件保持原样。
    @discardableResult func install(_ files: [String: Data]) throws -> [String] {
        let manager = FileManager.default
        var inserted: [String] = []
        do {
            for (name, data) in files {
                guard Self.safeFilename(name) else { throw DomainError.invalid("附件路径无效。") }
                let destination = root.appendingPathComponent(name)
                if manager.fileExists(atPath: destination.path) {
                    guard try Data(contentsOf: destination) == data else { throw DomainError.invalid("本机已有同编号的不同图片，未替换资料。") }
                    continue
                }
                let temporary = root.appendingPathComponent(".staging-\(UUID().uuidString)")
                do {
                    try data.write(to: temporary, options: .atomic)
                    try manager.moveItem(at: temporary, to: destination)
                } catch { try? manager.removeItem(at: temporary); throw error }
                inserted.append(name)
            }
            return inserted
        } catch { remove(inserted); throw error }
    }

    func remove(_ filenames: [String]) {
        for name in filenames where Self.safeFilename(name) { try? FileManager.default.removeItem(at: root.appendingPathComponent(name)) }
    }

    func collect(referenced: [Attachment]) throws {
        let retained = Set(referenced.map(\.filename))
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        for url in files where !retained.contains(url.lastPathComponent) &&
            (Self.safeFilename(url.lastPathComponent) || url.lastPathComponent.hasPrefix(".staging-")) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func safeFilename(_ name: String) -> Bool {
        guard name.hasSuffix(".png"), let id = UUID(uuidString: String(name.dropLast(4))) else { return false }
        return name == "\(id.uuidString).png"
    }

    static func validatePNG(_ data: Data, attachment: Attachment) throws {
        try attachment.validate()
        let bytes = [UInt8](data.prefix(24))
        guard data.count == attachment.byteCount, bytes.count == 24,
              Array(bytes[0..<8]) == [137, 80, 78, 71, 13, 10, 26, 10],
              Array(bytes[12..<16]) == [73, 72, 68, 82] else { throw DomainError.invalid("图片文件无效。") }
        let width = bytes[16..<20].reduce(0) { ($0 << 8) | Int($1) }
        let height = bytes[20..<24].reduce(0) { ($0 << 8) | Int($1) }
        guard width == attachment.width, height == attachment.height else { throw DomainError.invalid("图片尺寸与清单不符。") }
    }
}
