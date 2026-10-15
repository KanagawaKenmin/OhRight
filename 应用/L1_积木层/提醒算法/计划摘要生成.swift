// 所属层级：L1 积木层
// 文件职责：按未来触发日期生成真实计划摘要。
// 输入：事项、触发时刻；输出：排序与有限长度摘要。
// 依赖：L0、Foundation；不把打开页面算作进度。
import Foundation

enum PlanSummary {
    static func sorted(_ items: [Item], at date: Date, calendar: Calendar) -> [Item] {
        items.filter { $0.kind == .plan && $0.status == .active }.sorted {
            let left = $0.deadline?.boundary ?? .distantFuture
            let right = $1.deadline?.boundary ?? .distantFuture
            if left != right { return left < right }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    static func body(items: [Item], at date: Date, calendar: Calendar) -> String {
        let plans = sorted(items, at: date, calendar: calendar)
        let lines = plans.prefix(3).map { item in
            let due = item.deadline!
            let status = due.boundary <= date ? "逾期" : due.label
            let action = item.nextAction.isEmpty ? "看看下一小步" : item.nextAction
            return "\(String(item.title.prefix(24)))（\(status)）：\(String(action.prefix(30)))"
        }
        let suffix = plans.count > 3 ? "；另有 \(plans.count - 3) 项" : ""
        return String((lines.joined(separator: "；") + suffix).prefix(120))
    }
}
