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
        .executableTarget(
            name: "OrpytApp",
            path: "Sources"
        ),
    ]
)
