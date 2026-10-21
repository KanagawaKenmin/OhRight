// 测试边界：固定 v1 原始 JSON，与 v2 编码器独立。
// 输入：旧版本字段；输出：迁移和备份兼容测试样本。
// 不通过新对象删除字段制造“旧备份”。
import Foundation

enum LegacyJSON {
    static let item = #"""
    {"id":"00000000-0000-0000-0000-000000000001","kind":"idea","title":"原始标题",
     "body":"不要把 *星号* 变格式","status":"archived","createdAt":0,"updatedAt":60,
     "nextAction":"","effortMinutes":17,"reminderEnabled":true,"resumeStatus":"active",
     "beforeDeleteStatus":"active","steps":[],"entries":[
      {"id":"00000000-0000-0000-0000-000000000002","kind":"thought","text":"file_name_value",
       "createdAt":30,"previousText":"*保留原文*","editedAt":45} ]}
    """#
    static let preferences = #"""
    {"mode":"local","enabled":false,"timePolicy":"avoidQuiet",
     "quietIntervals":[{"id":"00000000-0000-0000-0000-000000000003","startMinute":1380,"endMinute":540}],
     "ideaDailyLimit":1,"digestEnabled":true,"digestMinute":1230,"contentPreview":true,"soundEnabled":false}
    """#
    static let draft = #"""
    {"text":"旧草稿 *原文*","nextAction":"下一步","dueDate":86400,"hasExactTime":true,"effortMinutes":17}
    """#
    static let runtime = #"""
    {"intents":[],"history":[],"appliedRevision":-1,"omittedDeadlines":0,"capacityLimited":false,
     "timeZoneID":"Asia/Tokyo","handledActions":{},"snoozeActions":[],"requestedSnoozes":[],"resetQueue":false}
    """#
    static var workspace: Data {
        Data("""
        {"schemaVersion":1,"items":[\(item)],"preferences":\(preferences),"appearance":"dark",
         "lastMode":"idea","drafts":{"capture/idea":\(draft)},"revision":7,"randomSeed":42,"runtime":\(runtime)}
        """.utf8)
    }
    static var backup: Data {
        Data("""
        {"formatVersion":1,"exportedAt":1792026000000,"items":[\(item)],"preferences":\(preferences),"appearance":"dark"}
        """.utf8)
    }
}
