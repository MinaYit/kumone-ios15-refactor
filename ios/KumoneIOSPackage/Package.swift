// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KumoneIOSFeature",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "KumoneIOSFeature",
            targets: ["KumoneIOSFeature"]
        ),
    ],
    dependencies: [
        // Keep the dependency identity stable when this fork has a custom
        // repository directory name in an online build workspace.
        .package(name: "kumone", path: "../.."),
    ],
    targets: [
        .target(
            name: "KumoneIOSFeature",
            dependencies: [
                .product(name: "KumoneCore", package: "kumone"),
            ],
            path: "Sources/KumoneIOSFeature"
        ),
        .testTarget(
            name: "KumoneIOSFeatureTests",
            dependencies: [
                "KumoneIOSFeature"
            ]
        ),
    ]
)
