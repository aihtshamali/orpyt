// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Orpyt",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "Orpyt",
            targets: ["OrpytApp"]
        ),
    ],
    targets: [
        // Core library — all stores, views, formatters, models.
        // Internal types are accessible to both the app and the test target.
        .target(
            name: "OrpytCore",
            path: "Sources/OrpytCore"
        ),
        // Executable — only the @main entry point, AppDelegate, and controllers.
        .executableTarget(
            name: "OrpytApp",
            dependencies: ["OrpytCore"],
            path: "Sources/App"
        ),
        // Unit tests — can @testable import OrpytCore.
        .testTarget(
            name: "OrpytTests",
            dependencies: ["OrpytCore"],
            path: "Tests/OrpytTests"
        ),
    ]
)
