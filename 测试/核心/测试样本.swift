// 测试边界：为领域与排程测试提供固定时钟和确定数据。
// 输入：测试参数；输出：纯 Swift 样本，不读写用户资料。
import Foundation
#if canImport(OhRightCore)
@testable import OhRightCore
#else
@testable import OhRight
#endif

enum Samples {
    static let now = ISO8601DateFormatter().date(from: "2026-10-15T01:00:00Z")!
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }
    static func idea(_ title: String = "阳台换盏灯") -> Item {
        Item(kind: .idea, title: title, body: "还没想完整", createdAt: now.addingTimeInterval(-5 * 86400),
             updatedAt: now.addingTimeInterval(-5 * 86400))
    }
    static func plan(_ title: String = "交材料", due: Date = now.addingTimeInterval(2 * 86400)) -> Item {
        var item = Item(kind: .plan, title: title, body: "", createdAt: now.addingTimeInterval(-86400), updatedAt: now)
        item.deadline = Deadline(precision: .instant, value: due, timeZoneID: "Asia/Tokyo")
        item.nextAction = "找出去年版本"
        return item
    }
    static func workspace(_ items: [Item]) -> Workspace {
        var value = Workspace()
        value.items = items
        value.randomSeed = 42
        value.preferences.enabled = true
        return value
    }
}
