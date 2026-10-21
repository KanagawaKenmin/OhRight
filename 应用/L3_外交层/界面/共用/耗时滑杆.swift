// 所属层级：L3 外交层（界面）
// 文件职责：离散耗时选择及辅助调节；保留未操作的旧自定义值。
// 输入：可空分钟绑定；输出：仅写编辑草稿。
// 依赖：SwiftUI；滑杆、点选和 VoiceOver 共用预设。
import SwiftUI

struct EffortSlider: View {
    @Binding var minutes: Int?
    private let options: [Int?] = [nil, 5, 15, 30, 60, 120]
    private var index: Int { options.firstIndex(of: minutes) ?? 0 }
    private func label(_ value: Int?) -> String {
        guard let value else { return "不确定" }
        return value >= 60 && value % 60 == 0 ? "\(value / 60) 小时" : "\(value) 分钟"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("预计耗时", value: label(minutes))
            Slider(value: Binding(get: { Double(index) }, set: { minutes = options[Int($0.rounded())] }), in: 0...5, step: 1)
                .accessibilityLabel("预计耗时").accessibilityValue(label(minutes))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: minutes = options[min(index + 1, 5)]
                    case .decrement: minutes = options[max(index - 1, 0)]
                    @unknown default: break
                    }
                }
            HStack { ForEach(0..<6) { i in Rectangle().frame(width: 1, height: 6); if i < 5 { Spacer() } } }
                .accessibilityHidden(true)
            Menu("选择耗时") { ForEach(0..<6) { i in Button(label(options[i])) { minutes = options[i] } } }
                .frame(minHeight: 44)
        }
    }
}
