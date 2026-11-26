// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vassy",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "Vassy", path: "Sources/Vassy")
    ],
    swiftLanguageModes: [.v5]
)
