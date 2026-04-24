// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MinimalStreamingDemo",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(path: "../../"),
    ],
    targets: [
        .executableTarget(
            name: "MinimalStreamingDemo",
            dependencies: [
                .product(name: "ForgeLoopTUI", package: "ForgeLoopTUI"),
            ],
            path: "Sources"
        ),
    ],
    swiftLanguageModes: [.v6]
)
