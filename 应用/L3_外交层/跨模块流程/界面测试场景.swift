// 所属层级：L3 外交层（开发期装配）
// 文件职责：在既有 UI 测试隔离库准备功能用例的前置记录。
// 输入：显式 --uitest 与场景参数；输出：经过业务校验的单条琐事。
// 依赖：AppModel、ItemEditing；Release 不编译，不提供用户入口。
#if DEBUG
import Foundation

@MainActor enum UITestScenario {
    static func prepare(_ model: AppModel, arguments: [String]) throws {
        guard arguments.contains("--uitest"),
              let argument = arguments.first(where: { $0.hasPrefix("--uitest-fixture=") }) else { return }
        let name = String(argument.dropFirst("--uitest-fixture=".count))
        let title: String
        switch name {
        case "quick-actions": title = "需要处理的琐事"
        case "conversion": title = "从琐事开始"
        case "library": title = "只在搜索里出现"
        default: throw DomainError.invalid("无法识别界面测试场景。")
        }
        guard model.workspace.items.isEmpty else { throw DomainError.invalid("测试场景只允许准备空的隔离库。") }
        let item = try ItemEditing.create(draft: CaptureDraft(text: title), kind: .idea,
                                         now: Date(), timeZone: model.calendar.timeZone)
        var next = model.workspace
        next.items = [item]
        try model.commit(next, business: false, refresh: false)
    }
}
#endif
