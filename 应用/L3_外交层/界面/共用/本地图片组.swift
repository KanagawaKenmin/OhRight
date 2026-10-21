// 所属层级：L3 外交层（界面）
// 文件职责：按引用顺序展示离线图片，缩略缓存与原件分离。
// 输入：附件引用；输出：缩略图和可放大的原图预览。
// 依赖：AppModel、ImageIO；不加载任何远程图片。
import SwiftUI
import UIKit

@MainActor private enum ThumbnailCache {
    static let values: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 24 * 1024 * 1024
        cache.countLimit = 80
        return cache
    }()
}

struct AttachmentGallery: View {
    let attachments: [Attachment]
    @State private var preview: Attachment?
    var body: some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                        Button { preview = attachment } label: {
                            LocalAttachmentImage(attachment: attachment).frame(width: 150, height: 150).clipped()
                        }.buttonStyle(.plain).accessibilityLabel("查看图片 \(index + 1)")
                    }
                }
            }
            .sheet(item: $preview) { AttachmentPreview(attachment: $0) }
        }
    }
}

struct LocalAttachmentImage: View {
    let attachment: Attachment
    var fullSize = false
    @Environment(AppModel.self) private var model
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if failed { Label("图片暂时无法读取", systemImage: "photo.badge.exclamationmark").font(.caption) }
            else { ProgressView() }
        }
        .task(id: attachment.id) {
            let store = model.attachments
            let key = "\(store.root.path)/\(attachment.filename)" as NSString
            if !fullSize, let cached = ThumbnailCache.values.object(forKey: key) { image = cached; return }
            let reference = attachment, original = fullSize
            let bytes = await Task.detached(priority: .userInitiated) {
                guard let data = try? store.data(for: reference) else { return nil as Data? }
                return original ? data : PhotoImport.thumbnail(data)
            }.value
            guard !Task.isCancelled else { return }
            image = bytes.flatMap { UIImage(data: $0) }
            failed = image == nil
            if !fullSize, let image { ThumbnailCache.values.setObject(image, forKey: key, cost: 400 * 400 * 4) }
        }
    }
}

private struct AttachmentPreview: View {
    let attachment: Attachment
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                LocalAttachmentImage(attachment: attachment, fullSize: true)
                    .frame(width: 340 * scale, height: 500 * scale)
            }
            .navigationTitle("图片").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button(scale == 1 ? "放大" : "还原") { scale = scale == 1 ? 2 : 1 } }
            }
        }
    }
}
