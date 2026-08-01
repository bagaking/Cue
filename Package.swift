// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cue",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Cue", targets: ["Cue"]),
    ],
    targets: [
        .executableTarget(
            name: "Cue",
            path: "Sources/Cue",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
