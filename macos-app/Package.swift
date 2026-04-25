// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Loole",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Loole",
            path: "Sources/Loole",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
