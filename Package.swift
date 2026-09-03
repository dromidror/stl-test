// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "STLViewer",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "STLViewer",
            path: "Sources/STLViewer"
        )
    ]
)
