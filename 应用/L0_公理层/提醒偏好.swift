// 所属层级：L0 公理层
// 文件职责：定义提醒方式、免打扰和本地偏好。
// 主要输入：用户设置；输出：可持久化规则。
// 依赖：Foundation；对外接口：ReminderPreferences、QuietInterval。
// 禁止事项：云端不可用时不伪造成功能力。
import Foundation

enum ReminderMode: String, Codable, Sendable { case local, cloud }
enum TimePolicy: String, Codable, CaseIterable, Sendable { case avoidQuiet, allDay }
enum Appearance: String, Codable, CaseIterable, Sendable { case system, light, dark }

struct QuietInterval: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var startMinute: Int
    var endMinute: Int
    // 起止相同表示全天，避免一个看似有效的全天免打扰被误当作零区间。
    func contains(minute: Int) -> Bool {
        if startMinute == endMinute { return true }
        if startMinute < endMinute { return minute >= startMinute && minute < endMinute }
        return minute >= startMinute || minute < endMinute
    }
}

struct ReminderPreferences: Codable, Equatable, Sendable {
    var mode: ReminderMode = .local
    var enabled = false
    var timePolicy: TimePolicy = .avoidQuiet
    var quietIntervals = [QuietInterval(startMinute: 23 * 60, endMinute: 9 * 60)]
    var ideaDailyLimit = 1
    var digestEnabled = true
    var digestMinute = 20 * 60 + 30
    var contentPreview = true
    // 只为旧快照/备份保留的字段；声音功能已移除，不再用于设置或通知。
    var soundEnabled = false

    func allows(_ date: Date, calendar: Calendar) -> Bool {
        if timePolicy == .allDay { return true }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return !quietIntervals.contains { $0.contains(minute: minute) }
    }
}

struct Capabilities: Sendable {
    var localAvailable = true
    var cloudAvailable = false
    var unavailableReason = "云端尚未接入，目前使用本地规则。"
}

enum DomainError: LocalizedError {
    case invalid(String)
    case missingItem
    case cloudUnavailable
    var errorDescription: String? {
        switch self {
        case .invalid(let reason): reason
        case .missingItem: "这条内容已不存在，请返回列表重新查看。"
        case .cloudUnavailable: "云端尚未接入，本地模式继续可用。"
        }
    }
}
