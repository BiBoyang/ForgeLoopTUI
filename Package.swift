// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ForgeLoopTUI",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "ForgeLoopTUI",
            targets: ["ForgeLoopTUI"]
        ),
    ],
    targets: [
        .target(
            name: "ForgeLoopTUI",
            path: "Sources/ForgeLoopTUI"
        ),
        .testTarget(
            name: "ForgeLoopTUITests",
            dependencies: ["ForgeLoopTUI"],
            path: "Tests/ForgeLoopTUITests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
