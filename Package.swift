// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "YaikusStudio",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "YaikusCore", targets: ["YaikusCore"]),
        .executable(name: "YaikusStudio", targets: ["YaikusStudio"]),
    ],
    targets: [
        // UI-free logic: models, sources, agents, voice, render and the MCP server (all testable)
        .target(name: "YaikusCore"),
        // App SwiftUI
        .executableTarget(name: "YaikusStudio", dependencies: ["YaikusCore"]),
        .testTarget(name: "YaikusCoreTests", dependencies: ["YaikusCore"]),
    ]
)
