// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PointFocus",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PointFocus",
            path: "Sources/PointFocus"
        ),
        .testTarget(
            name: "PointFocusTests",
            dependencies: ["PointFocus"],
            path: "Tests/PointFocusTests"
        )
    ]
)
