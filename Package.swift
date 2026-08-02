// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cue",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Cue", targets: ["Cue"]),
    ],
    targets: [
        .target(
            name: "CueCore",
            path: "Sources/CueCore",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .executableTarget(
            name: "Cue",
            dependencies: ["CueCore"],
            path: "Sources/Cue",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
