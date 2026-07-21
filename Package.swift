// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SourceLeaf",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SourceLeafCore", targets: ["SourceLeafCore"]),
        .executable(name: "SourceLeaf", targets: ["SourceLeafApp"])
    ],
    targets: [
        .target(
            name: "SourceLeafCore",
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "SourceLeafApp",
            dependencies: ["SourceLeafCore"],
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("PDFKit"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "SourceLeafCoreTests",
            dependencies: ["SourceLeafCore"]
        )
    ]
)
