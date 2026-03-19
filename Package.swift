// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MacCleanerPro",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacCleanerPro", targets: ["MacCleanerPro"])
    ],
    targets: [
        .executableTarget(
            name: "MacCleanerPro",
            path: "Sources/MacCleanerPro"
        ),
        .testTarget(
            name: "MacCleanerProTests",
            dependencies: ["MacCleanerPro"],
            path: "Tests/MacCleanerProTests"
        )
    ]
)
