// 所属层级：L0 公理层
// 文件职责：明确日期型与时刻型截止，保留创建时区。
// 主要输入：本地日期或绝对时刻；输出：截止边界。
// 依赖：Foundation；对外接口：Deadline.boundary。
// 禁止事项：不使用当前时区静默改写已有截止。
import Foundation

struct Deadline: Codable, Equatable, Sendable {
    enum Precision: String, Codable, Sendable { case dateOnly, instant }
    var precision: Precision
    var value: Date
    var timeZoneID: String

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .gmt
        return calendar
    }
    var boundary: Date {
        if precision == .instant { return value }
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: value)) ?? value
    }
    var label: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = precision == .dateOnly ? "M月d日" : "M月d日 HH:mm"
        return formatter.string(from: value)
    }
}
