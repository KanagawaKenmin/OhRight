// 所属层级：L3 外交层（界面）
// 文件职责：按可选时长主动抽取一条琐事。
// 输入：空闲分钟数；输出：可阅读的卡片，不触发通知。
// 依赖：AppModel；未估时的内容仍可出现。
import SwiftUI

struct FreeTimeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 15
    @State private var selectedID: UUID?
    private var candidates: [Item] {
        model.workspace.items.filter { $0.kind == .idea && $0.status == .active && ($0.effortMinutes ?? 0) <= minutes }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ModeBackground(mode: .idea)
                ScrollView {
                    VStack(spacing: 24) {
                        Text("有一点空，就捡起一点念头。").font(.title2).frame(maxWidth: .infinity, alignment: .leading)
                        Picker("现在有多久", selection: $minutes) {
                            ForEach([5, 15, 30], id: \.self) { Text("\($0) 分钟").tag($0) }
                        }.pickerStyle(.segmented)
                        if let id = selectedID, let item = candidates.first(where: { $0.id == id }) {
                            NavigationLink(value: id) { ItemCard(item: item) }.buttonStyle(.plain)
                            Button("看看这个") { model.path = [id]; dismiss() }.buttonStyle(.borderedProminent)
                                .foregroundStyle(Color("OnAccent"))
                            Button("换一个") { choose() }.frame(minHeight: 44)
                        } else {
                            ContentUnavailableView("暂时没有合适的念头", systemImage: "sparkles",
                                                   description: Text("可以换个时长，或先记下一句。"))
                        }
                    }.padding(24)
                }
            }
            .navigationTitle("我现在有空").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { ItemDetailView(id: $0) }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { dismiss() } } }
            .onAppear { choose() }.onChange(of: minutes) { _, _ in choose() }.appFeedback()
        }.tint(AppPalette.teal)
    }

    private func choose() {
        let others = candidates.filter { $0.id != selectedID }
        selectedID = (others.isEmpty ? candidates : others).randomElement()?.id
    }
}
