// swift-tools-version: 6.0
// 所属层级：构建边界；职责：在非 iOS 环境验证纯 Swift 领域与规则。
// 输入：应用中的纯 Swift 文件；输出：OhRightCore 与测试套件。
// 依赖：Swift Package Manager；不包含 SwiftUI、SwiftData 或通知适配器。
import PackageDescription

let package = Package(
    name: "OhRightCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "OhRightCore", targets: ["OhRightCore"])],
    targets: [
        .target(name: "OhRightCore", path: "应用", exclude: [
            "L1_积木层/本地存储", "L3_外交层", "L0_公理层/模块说明.md",
            "L1_积木层/提醒算法/模块说明.md", "L1_积木层/资料备份/模块说明.md",
            "L2_流程层/记录模块/模块说明.md", "L2_流程层/计划模块/模块说明.md",
            "L2_流程层/提醒模块/模块说明.md"
        ], sources: [
            "L0_公理层", "L1_积木层/提醒算法", "L1_积木层/资料备份",
            "L2_流程层/记录模块", "L2_流程层/计划模块", "L2_流程层/提醒模块"
        ]),
        .testTarget(name: "OhRightCoreTests", dependencies: ["OhRightCore"], path: "测试/核心")
    ]
)
