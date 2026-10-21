// 所属层级：L3 外交层（界面）
// 文件职责：在本地草稿编辑时间，完成时一次提交，取消保持原值。
// 输入：时间段或回顾时间；输出：已校验事务。
// 依赖：AppModel；冲突保留草稿，不自动挪动回顾时间。
import SwiftUI

struct ReminderTimeEditor: View {
    let editQuiet: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var intervals: [QuietInterval] = []
    @State private var enabled = true
    @State private var minute = 1230
    @State private var loaded = false
    @State private var error: String?
    var body: some View {
        Form {
            if editQuiet {
                Section {
                    Toggle("免打扰", isOn: $enabled)
                    if !enabled { Text("夜间也可能收到提醒。").font(.caption).foregroundStyle(.secondary) }
                }
                if enabled {
                    ForEach($intervals) { $interval in
                        Section {
                            QuietIntervalRow(interval: $interval)
                            Button("删除时段", role: .destructive) { intervals.removeAll { $0.id == interval.id } }
                        }
                    }
                    Button("添加时段") { intervals.append(QuietInterval(startMinute: 720, endMinute: 780)) }
                }
            } else {
                DatePicker("回顾时间", selection: Binding(get: {
                    Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
                }, set: {
                    let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                    minute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                }), displayedComponents: .hourAndMinute)
            }
            if let error { Section { Text(error).foregroundStyle(.orange) } }
        }
        .navigationTitle(editQuiet ? "免打扰时段" : "回顾时间").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") {
                    var next = model.preferences
                    if editQuiet { next.quietIntervals = intervals; next.timePolicy = enabled ? .avoidQuiet : .allDay }
                    else { next.digestMinute = minute }
                    do { try model.savePreferences(next); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            intervals = model.preferences.quietIntervals
            enabled = model.preferences.timePolicy == .avoidQuiet
            minute = model.preferences.digestMinute
            loaded = true
        }
    }
}
