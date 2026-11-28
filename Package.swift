// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vassy",
    platforms: [.macOS(.v15)],
    dependencies: [
        // Downloads and installs updates. Pinned to an exact release.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .executableTarget(name: "Vassy",
                          dependencies: [.product(name: "Sparkle", package: "Sparkle")],
                          path: "Sources/Vassy")
    ],
    swiftLanguageModes: [.v5]
)
