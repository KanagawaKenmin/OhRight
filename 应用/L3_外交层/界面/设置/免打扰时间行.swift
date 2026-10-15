// 所属层级：L3 外交层（界面）
// 文件职责：编辑一个可跨午夜的每日时间带。
// 输入：偏好绑定；输出：分钟数；依赖：SwiftUI。
// 起止相同表示全天，明确告知用户。
import SwiftUI

struct QuietIntervalRow: View {
    @Binding var interval: QuietInterval
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker("开始免打扰", selection: timeBinding(\.startMinute), displayedComponents: .hourAndMinute)
            DatePicker("结束免打扰", selection: timeBinding(\.endMinute), displayedComponents: .hourAndMinute)
            if interval.startMinute == interval.endMinute {
                Text("起止相同：全天免打扰。").font(.caption).foregroundStyle(.orange)
            } else if interval.startMinute > interval.endMinute {
                Text("跨到第二天结束。").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 6)
    }

    private func timeBinding(_ key: WritableKeyPath<QuietInterval, Int>) -> Binding<Date> {
        Binding(get: {
            let minute = interval[keyPath: key]
            return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
        }, set: {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
            interval[keyPath: key] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        })
    }
}
