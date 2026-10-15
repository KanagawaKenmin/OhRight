// 所属层级：L3 外交层（界面）
// 文件职责：提供可访问的平铺检查项和新增操作。
// 输入：事项编号；输出：L2 进度命令。
// 依赖：AppModel、PlanProgress；不自动完成整个计划。
import SwiftUI

struct ChecklistView: View {
    let itemID: UUID
    @Environment(AppModel.self) private var model
    @State private var text = ""
    var body: some View {
        if let item = model.item(itemID) {
            VStack(alignment: .leading, spacing: 12) {
                Text("小步骤 · \(item.completedStepCount)/\(item.steps.count)").font(.headline)
                ForEach(item.steps) { step in
                    Button {
                        model.attempt {
                            try model.transformItem(itemID) { try PlanProgress.toggleStep(in: $0, stepID: step.id, now: Date()) }
                            if let current = model.item(itemID), !current.steps.isEmpty,
                               current.completedStepCount == current.steps.count {
                                model.notice = "步骤都完成了。整件事也做到了吗？"
                            }
                        }
                    } label: {
                        HStack(alignment: .top) {
                            Image(systemName: step.isDone ? "checkmark.square.fill" : "square")
                            Text(step.text).strikethrough(step.isDone).frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(minHeight: 44)
                    }.buttonStyle(.plain).accessibilityLabel("\(step.isDone ? "已完成" : "未完成")：\(step.text)")
                }
                HStack {
                    TextField("加一个小步骤", text: $text, axis: .vertical)
                    Button {
                        if model.attempt({ try model.transformItem(itemID) { try PlanProgress.addStep(to: $0, text: text, now: Date()) } }) {
                            text = ""
                        }
                    } label: { Image(systemName: "plus.circle.fill").frame(width: 44, height: 44) }
                        .accessibilityLabel("添加步骤").disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
