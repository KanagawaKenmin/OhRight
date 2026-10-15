// 所属层级：L1 积木层
// 文件职责：枚举真实自然日内允许的一分钟时刻。
// 输入：日边界、偏好、时钟；输出：可抽取的分钟数组。
// 依赖：Foundation、L0；按实际时刻推进，支持夏令时。
import Foundation

enum TimeSampling {
    static func minutes(on day: Date, after now: Date, calendar: Calendar,
                        preferences: ReminderPreferences) -> [Date] {
        guard let range = calendar.dateInterval(of: .day, for: day) else { return [] }
        var cursor = range.start
        var values: [Date] = []
        while cursor < range.end {
            if cursor >= now.addingTimeInterval(300), preferences.allows(cursor, calendar: calendar) {
                values.append(cursor)
            }
            cursor = cursor.addingTimeInterval(60)
        }
        return values
    }

    static func wallClock(minute: Int, on day: Date, calendar: Calendar) -> Date? {
        let start = calendar.startOfDay(for: day)
        var components = DateComponents()
        components.hour = minute / 60
        components.minute = minute % 60
        components.second = 0
        let result = calendar.nextDate(after: start.addingTimeInterval(-1), matching: components,
                                       matchingPolicy: .nextTime, repeatedTimePolicy: .first)
        return result.flatMap { calendar.isDate($0, inSameDayAs: day) ? $0 : nil }
    }

    static func nextAllowed(after date: Date, calendar: Calendar,
                            preferences: ReminderPreferences) -> Date? {
        // 最多检查八天；全日免打扰必须有限退出。
        var cursor = Date(timeIntervalSince1970: ceil(date.timeIntervalSince1970 / 60) * 60)
        for _ in 0..<(8 * 25 * 60) {
            if preferences.allows(cursor, calendar: calendar) { return cursor }
            cursor = cursor.addingTimeInterval(60)
        }
        return nil
    }
}
