// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Disclean",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "disclean", targets: ["disclean"]),
        .library(name: "DiscleanKit", targets: ["DiscleanKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2")
    ],
    targets: [
        .target(
            name: "DiscleanKit",
            resources: [.copy("Resources/rules"), .copy("Resources/release-keys.json")]
        ),
        .executableTarget(
            name: "disclean",
            dependencies: [
                "DiscleanKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "DiscleanApp",
            dependencies: ["DiscleanKit"]
        ),
        .executableTarget(
            name: "disclean-catalog",
            dependencies: ["DiscleanKit"]
        ),
        .testTarget(name: "DiscleanKitTests", dependencies: ["DiscleanKit"]),
        .testTarget(name: "IntegrationTests", dependencies: ["DiscleanKit"]),
    ]
)
