// 所属层级：L3 外交层
// 文件职责：将系统选择器数据转为有界、校正方向且去除元数据的静态 PNG。
// 输入：照片原始数据；输出：已落盘附件引用。
// 依赖：ImageIO、UniformTypeIdentifiers、L1 仓库；不申请整库权限。
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PhotoImport {
    static func validate(_ data: Data, attachment: Attachment) throws {
        try AttachmentStore.validatePNG(data, attachment: attachment)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              image.width == attachment.width, image.height == attachment.height else {
            throw DomainError.invalid("备份中有无法读取的图片，未替换任何资料。")
        }
    }
    static func save(_ data: Data, store: AttachmentStore) throws -> Attachment {
        guard data.count <= 50_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1 else {
            throw DomainError.invalid("请选择不超过 50 MB 的静态图片。")
        }
        for limit in [2048, 1536, 1024, 768] {
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: limit]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw DomainError.invalid("这张图片暂时无法读取，请选择其他图片。")
            }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
                throw DomainError.invalid("图片处理失败。")
            }
            // 只写新像素，不复制 EXIF/GPS；PNG 保留透明度。
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw DomainError.invalid("图片保存失败。") }
            if output.length <= Attachment.maximumBytes {
                return try store.savePNG(output as Data, width: image.width, height: image.height)
            }
        }
        throw DomainError.invalid("处理后图片仍超过 5 MB，请选择较小的图片。")
    }

    static func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 400] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
