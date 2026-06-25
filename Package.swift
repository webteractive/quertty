// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "quertty",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "QuerttyCore", targets: ["QuerttyCore"]),
    ],
    dependencies: [
        // Required: only Command Line Tools are installed (no full Xcode), so the
        // toolchain's XCTest / bundled Testing module aren't available to `swift test`.
        // The self-contained swift-testing package is the only headless-runnable option.
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.0.0"),
    ],
    targets: [
        .target(name: "QuerttyCore"),
        .testTarget(
            name: "QuerttyCoreTests",
            dependencies: [
                "QuerttyCore",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
