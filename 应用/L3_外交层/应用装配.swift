// 所属层级：L3 外交层
// 文件职责：启动应用并装配唯一资料仓库与通知适配器。
// 输入：系统生命周期；输出：根界面或可恢复的启动错误。
// 依赖：SwiftUI、SwiftData 仓库；不因启动失败清空资料。
import SwiftUI
import UserNotifications
import UIKit
import Observation

@MainActor @Observable final class Bootstrap {
    var model: AppModel?
    var error: String?
    func open() {
        do {
            #if DEBUG
            let inMemory = ProcessInfo.processInfo.arguments.contains("--uitest")
            #else
            let inMemory = false
            #endif
            model = try NotificationRouter.shared.resolveModel(inMemory: inMemory)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

@main struct OhRightApp: App {
    @State private var bootstrap = Bootstrap()
    @Environment(\.scenePhase) private var scenePhase

    init() { UNUserNotificationCenter.current().delegate = NotificationBridge.shared }

    var body: some Scene {
        WindowGroup {
            Group {
                if let model = bootstrap.model {
                    HomeView().environment(model)
                        .preferredColorScheme(colorScheme(model.workspace.appearance))
                        .task { await model.start() }
                        .onChange(of: scenePhase) { _, phase in
                            if phase == .active { model.queueRefresh() }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                            model.queueRefresh()
                        }
                } else {
                    ContentUnavailableView {
                        Label(bootstrap.error == nil ? "哦对了" : "资料暂时无法打开", systemImage: "sparkle")
                    } description: {
                        Text(bootstrap.error ?? "正在留住你的念头…")
                    } actions: {
                        if bootstrap.error != nil { Button("重新尝试") { bootstrap.open() } }
                    }
                }
            }
            .task { if bootstrap.model == nil && bootstrap.error == nil { bootstrap.open() } }
        }
    }

    private func colorScheme(_ appearance: Appearance) -> ColorScheme? {
        switch appearance { case .system: nil; case .light: .light; case .dark: .dark }
    }
}
