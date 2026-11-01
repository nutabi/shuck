// swift-tools-version: 6.2
// 6.2 is the oldest tools version that knows macOS 26, the engine's API floor (D-06).

import PackageDescription

let package = Package(
    name: "ShuckKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ShuckKit", targets: ["ShuckKit"]),
        .library(name: "ShuckExecution", targets: ["ShuckExecution"]),
        .library(name: "ShuckKitTestSupport", targets: ["ShuckKitTestSupport"]),
    ],
    targets: [
        // Tools, Scanning, Rules, Planning, Safety and History (PRD section 11.1). Resources holds the String Catalog
        // for the names and summaries of tools and sub-tools (NFR-L10N-001).
        .target(name: "ShuckKit", resources: [.process("Resources")]),
        // The only module that may mutate user files or launchd state (SAF-017, D-28).
        .target(name: "ShuckExecution", dependencies: ["ShuckKit"]),
        // Fixture-root harness and file factory, shared by engine and UI tests (SAF-016).
        .target(name: "ShuckKitTestSupport", dependencies: ["ShuckKit"]),
        .testTarget(name: "ShuckKitTests", dependencies: ["ShuckKit", "ShuckKitTestSupport"]),
        .testTarget(
            name: "ShuckExecutionTests", dependencies: ["ShuckExecution", "ShuckKit", "ShuckKitTestSupport"]),
    ]
)
