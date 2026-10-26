// 所属层级：L3 外交层（界面）
// 文件职责：展示一条可读摘要，按截止分组。
// 输入：Item；输出：不含写操作的卡片。
// 依赖：SwiftUI、领域；颜色之外保留文字状态。
import SwiftUI

enum PlanSection: String, CaseIterable, Identifiable {
    case overdue = "已逾期", today = "今天截止", soon = "未来七天", later = "以后", paused = "已暂停"
    var id: String { rawValue }
    static func of(_ item: Item, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> PlanSection {
        if item.status == .paused { return .paused }
        guard let due = item.deadline else { return .later }
        if due.boundary <= now { return .overdue }
        if calendar.isDate(due.value, inSameDayAs: now) { return .today }
        if due.boundary <= calendar.date(byAdding: .day, value: 7, to: now)! { return .soon }
        return .later
    }
}

struct ItemCard: View {
    let item: Item
    var minimumHeight: CGFloat = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if item.isStarred { Label("星标", systemImage: "star.fill").font(.caption).foregroundStyle(.secondary) }
            if let due = item.deadline {
                HStack {
                    Text(due.label).font(.caption.weight(.bold)).foregroundStyle(AppPalette.red)
                    Spacer()
                    if item.status != .active { Text(item.status.label).font(.caption) }
                }
            }
            Text(item.title).font(.system(.title3, design: .default, weight: .semibold))
                .foregroundStyle(.primary).multilineTextAlignment(.leading).lineLimit(3)
            if item.kind == .plan && !item.nextAction.isEmpty {
                Text("下一步：\(item.nextAction)").font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            } else if let entry = item.entries.last(where: { [.thought, .progress].contains($0.kind) }) {
                Text(ReadableText.plain(entry.text, format: entry.textFormat)).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            } else if !item.body.isEmpty {
                Text(ReadableText.plain(item.body, format: item.textFormat)).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            if !item.steps.isEmpty {
                Text("完成 \(item.completedStepCount) / \(item.steps.count) 步")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if !item.reminderEnabled || (item.mutedUntil ?? .distantPast) > Date() {
                Label("暂不提醒", systemImage: "bell.slash").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .leading).itemCard(item.kind)
        .accessibilityElement(children: .combine)
    }
}
