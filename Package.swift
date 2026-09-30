// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SwiftPurchases",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "SwiftPurchases",
            targets: ["SwiftPurchases"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SwiftPurchases",
            dependencies: []
        ),
        .testTarget(
            name: "SwiftPurchasesTests",
            dependencies: ["SwiftPurchases"]
        ),
    ]
)
