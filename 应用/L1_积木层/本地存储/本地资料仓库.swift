// 所属层级：L1 积木层
// 文件职责：通过 SwiftData 原子持久化完整领域快照。
// 输入：Workspace；输出：成功保存或明确错误。
// 依赖：SwiftData、L0 协议；不自动删库，不启用 CloudKit。
import Foundation
import SwiftData

@Model final class StoredWorkspace {
    @Attribute(.unique) var key: String
    var payload: Data
    init(key: String, payload: Data) { self.key = key; self.payload = payload }
}

@MainActor final class LocalWorkspaceRepository: WorkspaceRepository {
    let container: ModelContainer
    private let context: ModelContext

    /// 打开仓库前创建存储父目录；storeURL 供隔离磁盘测试使用，正式路径保持系统默认。
    init(inMemory: Bool = false, storeURL: URL? = nil) throws {
        let schema = Schema([StoredWorkspace.self])
        let configuration: ModelConfiguration
        if let storeURL {
            guard !inMemory && storeURL.isFileURL else { throw DomainError.invalid("存储位置需要是本地文件。") }
            configuration = ModelConfiguration("OhRight", schema: schema, url: storeURL, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration("OhRight", schema: schema, isStoredInMemoryOnly: inMemory,
                                               groupContainer: .none, cloudKitDatabase: .none)
        }
        if !inMemory {
            try FileManager.default.createDirectory(at: configuration.url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
        }
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func load() throws -> Workspace {
        if let stored = try context.fetch(FetchDescriptor<StoredWorkspace>()).first {
            let decoder = JSONDecoder()
            let value = try decoder.decode(Workspace.self, from: stored.payload)
            guard value.schemaVersion == 1 else { throw DomainError.invalid("资料版本无法识别，原资料已保留。") }
            return value
        }
        let initial = Workspace()
        try save(initial)
        return initial
    }

    func save(_ workspace: Workspace) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(workspace)
        do {
            if let stored = try context.fetch(FetchDescriptor<StoredWorkspace>()).first {
                stored.payload = data
            } else {
                context.insert(StoredWorkspace(key: "primary", payload: data))
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
