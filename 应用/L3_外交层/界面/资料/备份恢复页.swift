// 所属层级：L3 外交层（界面）
// 文件职责：导出含图 ZIP/Markdown，兼容旧 JSON 并确认整库替换。
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
    @State private var pendingRestore: BackupPackage?
    @State private var confirmRestore = false
    @State private var safetyFiles: [URL] = []
    @State private var working = false

    var body: some View {
        Form {
            Section("留一份在应用之外") {
                Button("导出完整备份（含图片）") {
                    prepareExport(readable: false)
                }
                Button("导出 Markdown 与图片") {
                    prepareExport(readable: true)
                }
                Text("备份包含私人内容。可以保存到“文件”或自己的 iCloud Drive；卸载前请先导出。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("恢复资料") {
                Button("选择备份（ZIP 或旧 JSON）") { importing = true }
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
        .disabled(working)
        .overlay { if working { ProgressView("正在处理备份…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .interactiveDismissDisabled(working).navigationBarBackButtonHidden(working)
        .navigationTitle("备份与恢复").navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $exporting, document: document, contentType: contentType, defaultFilename: filename) { result in
            switch result {
            case .success: model.notice = "文件已导出。"
            case .failure(let error): model.report(error)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.zip, .json]) { result in
            switch result {
            case .success(let url): stage(url)
            case .failure(let error): model.report(error)
            }
        }
        .confirmationDialog("替换当前全部资料？", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("确认整库恢复", role: .destructive) {
                if let backup = pendingRestore {
                    working = true
                    Task { @MainActor in
                        do { try await model.restore(backup) } catch { model.report(error) }
                        working = false
                        loadSafetyFiles()
                    }
                }
                pendingRestore = nil
            }
            Button("取消", role: .cancel) { pendingRestore = nil }
        } message: {
            if let backup = pendingRestore {
                Text("备份包含 \(backup.manifest.items.count) 条事项，导出于 \(backup.manifest.exportedAt.formatted(date: .abbreviated, time: .shortened))。")
            }
        }
        .onAppear { loadSafetyFiles() }.appFeedback()
    }

    private func stage(_ url: URL) {
        working = true
        Task { @MainActor in
            do { pendingRestore = try await model.readBackup(at: url); confirmRestore = true }
            catch { model.report(error) }
            working = false
        }
    }

    private func prepareExport(readable: Bool) {
        working = true
        let snapshot = model.workspace, store = model.attachments
        Task { @MainActor in
            do {
                let bytes = try await Task.detached(priority: .userInitiated) {
                    try CompleteBackup.encode(snapshot, store: store, readable: readable)
                }.value
                document = ExportDocument(data: bytes)
                contentType = .zip
                filename = readable ? "哦对了-便条" : "哦对了-备份"
                exporting = true
            } catch { model.report(error) }
            working = false
        }
    }

    private func loadSafetyFiles() {
        guard let root = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: false) else { return }
        safetyFiles = (try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("SafetyBackups"),
            includingPropertiesForKeys: [.creationDateKey]))?.filter { ["json", "zip"].contains($0.pathExtension) }.sorted {
                ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) >
                ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
            } ?? []
    }
}
