// swift-tools-version:5.5
// BridgeMobile Swift Package
//
// 用意：用 Swift Package Manager 實際編譯 bridge-mobile iOS SDK，
//       確保 Swift 語法合法、所有 85 tokens 載入無誤。
//
// 用法：
//   cd packages/bridge-mobile/ios
//   swift build                  # 編譯
//   swift run BridgeMobileTest   # 跑整合測試

import PackageDescription

let package = Package(
    name: "BridgeMobile",
    products: [
        .library(name: "BridgeMobile", targets: ["BridgeMobile"]),
        .executable(name: "BridgeMobileTest", targets: ["BridgeMobileTest"]),
    ],
    targets: [
        .target(
            name: "BridgeMobile",
            dependencies: [],
            path: ".",
            exclude: ["Tests", "BridgeMobile.podspec", "Package.swift"],
            sources: ["BridgeMobile.swift", "BridgeMobile+Tokens.swift"]
        ),
        .executableTarget(
            name: "BridgeMobileTest",
            dependencies: ["BridgeMobile"],
            path: "Tests"
        ),
    ]
)
