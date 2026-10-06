// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClauthBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClauthBar",
            path: "Sources/ClauthBar"
        ),
    ]
)
