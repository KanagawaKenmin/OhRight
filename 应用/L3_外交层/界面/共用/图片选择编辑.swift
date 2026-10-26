// 所属层级：L3 外交层（界面）
// 文件职责：按需选择静态照片、顺序导入并修改草稿引用。
// 输入：照片选择结果；输出：本地图片引用；关闭后仍完成草稿保存。
// 依赖：PhotosUI、图片导入、AppModel；失败不添加悬空引用。
import SwiftUI
import PhotosUI

struct PhotoAttachmentEditor: View {
    @Binding var attachments: [Attachment]
    @Binding var working: Bool
    var existingCount = 0
    var kind: ItemKind = .idea
    var format: Binding<TextFormat>?
    var preview: Binding<Bool>?
    var persist: () -> Void
    @Environment(AppModel.self) private var model
    @State private var selection: [PhotosPickerItem] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) { picker; formatTools }
                VStack(alignment: .leading, spacing: 4) { picker; formatTools }
            }
            AttachmentGallery(attachments: attachments)
            ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                HStack {
                    Text("图片 \(index + 1)")
                    Spacer()
                    Button("前移") {
                        attachments.swapAt(index, index - 1); persist()
                    }.disabled(index == 0 || working).frame(minHeight: 44)
                    Button("移除", role: .destructive) {
                        attachments.removeAll { $0.id == attachment.id }; persist()
                    }.disabled(working).frame(minHeight: 44)
                }
            }
        }
        .onChange(of: selection) { _, photos in
            guard !photos.isEmpty, !working else { return }
            working = true
            Task { @MainActor in
                for photo in photos {
                    do {
                        guard existingCount + attachments.count < Attachment.maximumPerItem else {
                            throw DomainError.invalid("每条事项及记录最多 20 张图片。")
                        }
                        guard let data = try await photo.loadTransferable(type: Data.self) else {
                            throw DomainError.invalid("无法读取所选图片。")
                        }
                        let store = model.attachments
                        let reference = try await Task.detached(priority: .userInitiated) {
                            try PhotoImport.save(data, store: store)
                        }.value
                        attachments.append(reference)
                        persist()
                    } catch { model.report(error) }
                }
                selection = []
                working = false
            }
        }
    }

    private var picker: some View {
        PhotosPicker(selection: $selection, maxSelectionCount: max(1, 20 - existingCount - attachments.count),
                     matching: .images, photoLibrary: .shared()) {
            Label(working ? "正在导入…" : "图片", systemImage: "photo.badge.plus").fixedSize(horizontal: true, vertical: true)
        }
        .buttonStyle(EditorToolStyle(kind: kind)).accessibilityLabel(working ? "正在导入图片" : "添加图片")
        .disabled(working || existingCount + attachments.count >= Attachment.maximumPerItem)
    }

    @ViewBuilder private var formatTools: some View {
        if let format, let preview { RecordFormatTools(format: format, preview: preview, kind: kind) }
    }
}
