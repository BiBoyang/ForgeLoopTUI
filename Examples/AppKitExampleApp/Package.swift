// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppKitExampleApp",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(path: "../../"),
    ],
    targets: [
        .executableTarget(
            name: "AppKitExampleApp",
            dependencies: [
                .product(name: "ForgeLoopTUI", package: "ForgeLoopTUI"),
            ],
            path: "Sources"
        ),
    ],
    swiftLanguageModes: [.v6]
)

