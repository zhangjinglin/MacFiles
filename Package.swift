// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyFiles",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MyFiles",
            path: "Sources/MyFiles"
        )
    ]
)
