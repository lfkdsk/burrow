// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Burrow",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Burrow",
            path: "Sources/Burrow",
            resources: [.copy("Resources/Planets")]
        )
    ]
)
