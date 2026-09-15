// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Mole",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Swift Testing is bundled with Xcode 16+; pinned here so the package
        // also tests under standalone CommandLineTools toolchains.
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.12.0"),
    ],
    targets: [
        .executableTarget(
            name: "Mole",
            path: "Sources/MoleApp",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MoleTests",
            dependencies: [
                "Mole",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/MoleTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
