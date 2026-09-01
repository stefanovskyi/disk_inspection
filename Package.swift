// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SpaceLens",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SpaceLens", targets: ["SpaceLens"])
    ],
    targets: [
        .executableTarget(
            name: "SpaceLens",
            path: "Sources/SpaceLens",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "SpaceLensTests",
            dependencies: ["SpaceLens"],
            path: "Tests/SpaceLensTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
