// 所属层级：L3 外交层（界面边界）
// 文件职责：适配系统文件导出器的数据文档。
// 输入：已编码资料；输出：用户选择位置的文件。
// 依赖：SwiftUI、UniformTypeIdentifiers；不自行上传。
import SwiftUI
import UniformTypeIdentifiers

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText, UTType(filenameExtension: "md") ?? .plainText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
