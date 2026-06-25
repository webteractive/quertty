// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "quertty",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "QuerttyCore", targets: ["QuerttyCore"]),
    ],
    targets: [
        .target(name: "QuerttyCore"),
        .testTarget(name: "QuerttyCoreTests", dependencies: ["QuerttyCore"]),
    ]
)
