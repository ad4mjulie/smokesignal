// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SmokeSignalCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "SmokeSignalCore", targets: ["SmokeSignalCore"]),
    ],
    targets: [
        .target(name: "SmokeSignalCore"),
        .testTarget(name: "SmokeSignalCoreTests", dependencies: ["SmokeSignalCore"]),
    ]
)

