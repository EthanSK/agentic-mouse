// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AgenticMouse",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "ScimitarKit", targets: ["ScimitarKit"]),
        .executable(name: "agentic-mouse", targets: ["AgenticMouseApp"]),
        .executable(name: "agentic-mouse-doctor", targets: ["ScimitarDoctor"])
    ],
    targets: [
        // Thin C shim that dlopen()s the proprietary iCUE SDK at runtime.
        // No Corsair headers or binaries are vendored into this repository; the
        // ABI is re-declared here so the project builds and tests without the SDK.
        .target(
            name: "CICUEBridge",
            path: "Sources/CICUEBridge"
        ),

        // Injectable core and macOS target-discovery adapters. The pure state
        // machines remain testable without a mouse, Hue, iCUE, or AX grants;
        // the focus adapters use AppKit's workspace/process APIs.
        .target(
            name: "ScimitarKit",
            dependencies: ["CICUEBridge"],
            path: "Sources/ScimitarKit"
        ),

        // AppKit/SwiftUI shell: non-activating HUD panel + menu bar item.
        .target(
            name: "ScimitarUI",
            dependencies: ["ScimitarKit"],
            path: "Sources/ScimitarUI"
        ),

        .executableTarget(
            name: "AgenticMouseApp",
            dependencies: ["ScimitarKit", "ScimitarUI"],
            path: "Sources/AgenticMouseApp"
        ),

        .executableTarget(
            name: "ScimitarDoctor",
            dependencies: ["ScimitarKit"],
            path: "Sources/ScimitarDoctor"
        ),

        .testTarget(
            name: "ScimitarKitTests",
            dependencies: ["ScimitarKit"],
            path: "Tests/ScimitarKitTests"
        )
    ]
)
