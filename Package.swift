// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HerdCode",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "HerdCode",
            path: "Sources/HerdCode",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .testTarget(
            name: "HerdCodeTests",
            dependencies: ["HerdCode"],
            path: "Tests/HerdCodeTests"
        ),
    ]
)
