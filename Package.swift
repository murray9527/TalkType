// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TalkType",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TalkType", targets: ["TalkType"])
    ],
    dependencies: [
        // whisper.cpp Swift bindings
        .package(url: "https://github.com/ggml-org/whisper.spm", branch: "master"),
        // GRDB for SQLite
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "TalkType",
            dependencies: [
                .product(name: "whisper", package: "whisper.spm"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/TalkType",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "TalkTypeTests",
            dependencies: ["TalkType"],
            path: "Tests/TalkTypeTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
