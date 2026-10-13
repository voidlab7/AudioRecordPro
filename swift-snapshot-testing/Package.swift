// swift-tools-version:5.9
// LOOP-05: 精简 manifest —— 项目只用 SnapshotTesting 主产品（零依赖）。
// 原版（tools 6.0，含 swift-syntax/custom-dump 远程依赖）备份在 Package.swift.tools60.orig。
// 精简原因：Xcode 包解析的 sandbox-exec 在本机执行环境必死（sandbox_apply EPERM），
// 砍掉远程依赖后包图纯本地，绕开沙箱化 checkout。
import PackageDescription

let package = Package(
    name: "swift-snapshot-testing",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6),
    ],
    products: [
        .library(
            name: "SnapshotTesting",
            targets: ["SnapshotTesting"]
        ),
    ],
    targets: [
        .target(name: "SnapshotTesting")
    ]
)
