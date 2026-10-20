// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Strata",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Strata", targets: ["Strata"]),
        .executable(name: "StrataReadOnlyScanner", targets: ["StrataReadOnlyScanner"])
    ],
    targets: [
        .executableTarget(
            name: "Strata",
            dependencies: ["ReadOnlyScanCore"],
            path: "Sources/Strata"
        ),
        .target(name: "ReadOnlyScanCore"),
        .executableTarget(name: "StrataReadOnlyScanner", dependencies: ["ReadOnlyScanCore"]),
        .testTarget(
            name: "StrataTests",
            dependencies: ["Strata", "ReadOnlyScanCore"],
            path: "Tests/StrataTests"
        )
    ]
)
