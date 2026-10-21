// 所属层级：L0 公理层
// 文件职责：定义文字格式、本地图片引用与附件限额。
// 输入：内容元数据；输出：可编码引用和引用集合。
// 依赖：Foundation；不访问文件、照片或界面。
import Foundation

enum TextFormat: String, Codable, Sendable { case plain, markdown }

struct Attachment: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var filename: String
    var mediaType: String = "image/png"
    var width: Int
    var height: Int
    var byteCount: Int
    static let maximumBytes = 5_000_000
    static let maximumPerItem = 20

    func validate() throws {
        guard filename == "\(id.uuidString).png", mediaType == "image/png",
              (1...2048).contains(width), (1...2048).contains(height),
              (1...Self.maximumBytes).contains(byteCount) else {
            throw DomainError.invalid("图片信息无效，未替换任何资料。")
        }
    }
}

extension Item {
    var allAttachments: [Attachment] {
        attachments + entries.flatMap { $0.attachments + $0.previousAttachments }
    }
}

extension Workspace {
    var allAttachments: [Attachment] { items.flatMap(\.allAttachments) + drafts.values.flatMap(\.attachments) }
}

struct NotificationOnboarding: Codable, Equatable, Sendable {
    var version = 0
    var isNewInstallation = true
    var userChoseReminder = false
    var offerEnable = false
}
