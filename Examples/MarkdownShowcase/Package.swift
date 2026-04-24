// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MarkdownShowcase",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(path: "../../"),
    ],
    targets: [
        .executableTarget(
            name: "MarkdownShowcase",
            dependencies: [
                .product(name: "ForgeLoopTUI", package: "ForgeLoopTUI"),
            ],
            path: "Sources"
        ),
    ],
    swiftLanguageModes: [.v6]
)
