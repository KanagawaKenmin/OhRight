// 所属层级：L3 外交层（界面）
// 文件职责：导出 JSON/Markdown，明确确认整库替换与回退。
// 输入：用户选择的文件；输出：应用恢复命令。
// 依赖：AppModel、FileDocument；失败不退出或清空原库。
import SwiftUI
import UniformTypeIdentifiers

struct BackupView: View {
    @Environment(AppModel.self) private var model
    @State private var document = ExportDocument(data: Data())
    @State private var exporting = false
    @State private var importing = false
    @State private var contentType: UTType = .json
    @State private var filename = "哦对了-备份"
    @State private var pendingRestore: BackupEnvelope?
    @State private var confirmRestore = false
    @State private var safetyFiles: [URL] = []

    var body: some View {
        Form {
            Section("留一份在应用之外") {
                Button("导出完整 JSON 备份") {
                    model.attempt {
                        document = ExportDocument(data: try BackupCodec.encode(model.workspace))
                        contentType = .json
                        filename = "哦对了-备份-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))"
                        exporting = true
                    }
                }
                Button("导出可阅读的 Markdown") {
                    document = ExportDocument(data: Data(BackupCodec.markdown(model.workspace).utf8))
                    contentType = UTType(filenameExtension: "md") ?? .plainText
                    filename = "哦对了-便条"
                    exporting = true
                }
                Text("备份包含私人内容。可以保存到“文件”或自己的 iCloud Drive；卸载前请先导出。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("恢复资料") {
                Button("选择 JSON 备份") { importing = true }
                Text("恢复将替换全部事项及提醒偏好。确认前会检查文件，恢复前另留本机安全快照。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !safetyFiles.isEmpty {
                Section("恢复前的本机快照") {
                    ForEach(safetyFiles, id: \.self) { url in
                        Button {
                            stage(url)
                        } label: {
                            let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                            Text("恢复前快照 · \(date.formatted(date: .abbreviated, time: .shortened))")
                        }
                    }
                    Text("这些快照也会随应用卸载而丢失，不替代外部备份。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("备份与恢复").navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $exporting, document: document, contentType: contentType, defaultFilename: filename) { result in
            switch result {
            case .success: model.notice = "文件已导出。"
            case .failure(let error): model.message = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): stage(url)
            case .failure(let error): model.message = error.localizedDescription
            }
        }
        .confirmationDialog("替换当前全部资料？", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("确认整库恢复", role: .destructive) {
                if let backup = pendingRestore { model.attempt { try model.restore(backup) } }
                pendingRestore = nil
                loadSafetyFiles()
            }
            Button("取消", role: .cancel) { pendingRestore = nil }
        } message: {
            if let backup = pendingRestore {
                Text("备份包含 \(backup.items.count) 条事项，导出于 \(backup.exportedAt.formatted(date: .abbreviated, time: .shortened))。")
            }
        }
        .onAppear { loadSafetyFiles() }.appFeedback()
    }

    private func stage(_ url: URL) {
        model.attempt { pendingRestore = try model.readBackup(at: url); confirmRestore = true }
    }

    private func loadSafetyFiles() {
        guard let root = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: false) else { return }
        safetyFiles = (try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("SafetyBackups"),
            includingPropertiesForKeys: [.creationDateKey]))?.filter { $0.pathExtension == "json" }.sorted {
                ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) >
                ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
            } ?? []
    }
}
