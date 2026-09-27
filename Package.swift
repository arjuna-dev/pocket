// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Pocket",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Pocket",
            targets: ["Pocket"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Pocket",
            path: "Sources/Pocket"
        )
    ],
    swiftLanguageModes: [.v5]
)
