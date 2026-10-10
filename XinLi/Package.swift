// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "XinLi",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LunarCore", targets: ["LunarCore"]),
        .executable(name: "XinLi", targets: ["XinLi"]),
    ],
    targets: [
        // 纯计算逻辑：农历、干支、节气、节日、调休，不依赖 AppKit
        .target(name: "LunarCore", resources: [.copy("Resources/LunarGo")]),
        // 菜单栏应用
        .executableTarget(name: "XinLi", dependencies: ["LunarCore"], resources: [.process("Resources")]),
    ]
)
