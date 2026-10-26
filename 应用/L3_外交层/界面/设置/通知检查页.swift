// 所属层级：L3 外交层（界面）
// 文件职责：发起用户明确选择的测试并导出脱敏报告。
// 输入：测试操作；输出：系统回读的可见结果。
// 依赖：通知适配器；不声称真机已通过未执行的测试。
import SwiftUI
import UniformTypeIdentifiers

struct NotificationDiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @State private var rows: [(id: String, title: String, date: Date?)] = []
    @State private var working = false
    @State private var result = ""
    @State private var exporting = false
    @State private var document = ExportDocument(data: Data())

    var body: some View {
        List {
            Section("个人试用检查") {
                Text("安排成功表示请求已交给系统；锁屏能否看到仍需在手机上实际观察。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("两分钟后发一条测试通知") {
                    run {
                        guard try await model.delivery.requestPermission() else { throw DomainError.invalid("请先在系统设置允许通知。") }
                        try await model.delivery.testNotification()
                        result = "已安排两分钟后测试。现在可以退出应用并锁屏。"
                    }
                }.disabled(working)
                Button("检查 32 条容量并立即撤销") {
                    run {
                        guard try await model.delivery.requestPermission() else { throw DomainError.invalid("请先允许通知。") }
                        let count = try await model.delivery.probeCapacity()
                        result = "系统接受 \(count)/32 条测试请求；测试请求已撤销。"
                    }
                }.disabled(working)
                Button("清除测试通知") { run { await model.delivery.clearTestNotifications(); result = "测试通知已清除。" } }
                if !result.isEmpty { Text(result).font(.subheadline) }
            }
            Section("系统待触发 · \(rows.count) 条") {
                LabeledContent("系统权限", value: model.permissionLabel)
                if let end = model.workspace.runtime.coverageEnd {
                    LabeledContent("本地计算到", value: end.formatted(date: .abbreviated, time: .shortened))
                }
                if let error = model.workspace.runtime.lastError { Text(error).font(.caption) }
                if let error = model.diagnosticError { Text(error).font(.caption) }
                Button("重新安排提醒") { run { await model.refreshNotifications() } }
                Button("刷新队列") { run { } }
                ForEach(rows, id: \.id) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.title)
                        Text(row.id).font(.caption2).foregroundStyle(.secondary)
                        if let date = row.date { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption) }
                    }
                }
            }
            Section {
                Button("导出脱敏排程报告") {
                    model.attempt { document = ExportDocument(data: try model.diagnosticData()); exporting = true }
                }
                Text("报告包含请求编号、时间与错误，不含便条正文。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("故障排查").navigationBarTitleDisplayMode(.inline)
        .task { rows = await model.delivery.diagnosticRows() }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "哦对了-排程报告") { result in
            if case .failure(let error) = result { model.report(error) }
        }.appFeedback()
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        working = true
        Task { @MainActor in
            do { try await operation() } catch { model.report(error) }
            rows = await model.delivery.diagnosticRows()
            working = false
        }
    }
}
