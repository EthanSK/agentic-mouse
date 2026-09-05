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
        .executable(
            name: "agentic-mouse-supervisor",
            targets: ["AgenticMouseSupervisor"]
        ),
        .executable(name: "agentic-mouse-doctor", targets: ["ScimitarDoctor"]),
        .executable(name: "agentic-mouse-site", targets: ["ShowcaseExporter"])
    ],
    targets: [
        // Thin C shim that dlopen()s the proprietary iCUE SDK at runtime.
        // No Corsair headers or binaries are vendored into this repository; the
        // ABI is re-declared here so the project builds and tests without the SDK.
        .target(
            name: "CICUEBridge",
            path: "Sources/CICUEBridge"
        ),

        // Small IOKit USB shim for the exact Naga vendor protocol. It exposes
        // only device discovery and one acknowledged 90-byte control exchange;
        // packet construction and exact-device safety checks remain in Swift.
        .target(
            name: "CRazerUSBTransport",
            path: "Sources/CRazerUSBTransport",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation")
            ]
        ),

        // Injectable core and macOS target-discovery adapters. The pure state
        // machines remain testable without a mouse, Hue, iCUE, or AX grants;
        // the focus adapters use AppKit's workspace/process APIs.
        .target(
            name: "ScimitarKit",
            dependencies: ["CICUEBridge", "CRazerUSBTransport"],
            path: "Sources/ScimitarKit",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
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
            name: "AgenticMouseSupervisor",
            path: "Sources/AgenticMouseSupervisor"
        ),

        .executableTarget(
            name: "ScimitarDoctor",
            dependencies: ["ScimitarKit"],
            path: "Sources/ScimitarDoctor"
        ),

        .executableTarget(
            name: "ShowcaseExporter",
            dependencies: ["ScimitarKit"],
            path: "Sources/ShowcaseExporter"
        ),

        .testTarget(
            name: "ScimitarKitTests",
            dependencies: ["ScimitarKit"],
            path: "Tests/ScimitarKitTests"
        ),

        .testTarget(
            name: "AgenticMouseAppTests",
            dependencies: ["AgenticMouseApp"],
            path: "Tests/AgenticMouseAppTests"
        ),

        .testTarget(
            name: "AgenticMouseSupervisorTests",
            dependencies: ["AgenticMouseSupervisor"],
            path: "Tests/AgenticMouseSupervisorTests"
        ),

        .testTarget(
            name: "ScimitarUITests",
            dependencies: ["ScimitarUI"],
            path: "Tests/ScimitarUITests"
        )
    ]
)
