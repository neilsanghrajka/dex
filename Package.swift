// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Dex",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Dex", targets: ["Dex"])
    ],
    targets: [
        .executableTarget(
            name: "Dex",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "DexTests",
            dependencies: ["Dex"]
        )
    ]
)
