// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MinimalAIApp",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(path: "../../"),
    ],
    targets: [
        .executableTarget(
            name: "MinimalAIApp",
            dependencies: [
                .product(name: "ForgeLoopTUI", package: "ForgeLoopTUI"),
            ],
            path: "Sources"
        ),
    ],
    swiftLanguageModes: [.v6]
)
