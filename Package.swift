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
        .executable(
            name: "OrpytAgentBridge",
            targets: ["OrpytAgentBridge"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
    ],
    targets: [
        // Core library — all stores, views, formatters, models.
        // Internal types are accessible to both the app and the test target.
        .target(
            name: "OrpytCore",
            path: "Sources/OrpytCore",
            swiftSettings: [
                .define("DIRECT_DISTRIBUTION"),
                .define("DEBUG", .when(configuration: .debug)),
            ]
        ),
        // Executable — only the @main entry point, AppDelegate, and controllers.
        .executableTarget(
            name: "OrpytApp",
            dependencies: [
                "OrpytCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/App",
            swiftSettings: [
                .define("DIRECT_DISTRIBUTION"),
                .define("DEBUG", .when(configuration: .debug)),
            ]
        ),
        .executableTarget(
            name: "OrpytAgentBridge",
            dependencies: ["OrpytCore"],
            path: "Sources/AgentBridge"
        ),
        // Unit tests — can @testable import OrpytCore.
        .testTarget(
            name: "OrpytTests",
            dependencies: ["OrpytCore"],
            path: "Tests/OrpytTests"
        ),
    ]
)
