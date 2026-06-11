// swift-tools-version: 6.2
import PackageDescription

let kSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6)
]

let kPackage = Package(
    name: "SwiftCloneDetector",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "swift-clone-detector",
            targets: ["swift-clone-detector"]
        ),
        .library(
            name: "SwiftCloneDetectorKit",
            targets: ["SwiftCloneDetectorKit"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-syntax.git",
            "600.0.0"..<"700.0.0"
        )
    ],
    targets: [
        .target(
            name: "SwiftCloneDetectorKit",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ],
            swiftSettings: kSwiftSettings
        ),
        .executableTarget(
            name: "swift-clone-detector",
            dependencies: ["SwiftCloneDetectorKit"],
            swiftSettings: kSwiftSettings
        ),
        .testTarget(
            name: "SwiftCloneDetectorKitTests",
            dependencies: ["SwiftCloneDetectorKit"],
            swiftSettings: kSwiftSettings
        )
    ]
)
