// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pesu",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "PesuApp", targets: ["PesuApp"])
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite"
        ),
        .executableTarget(
            name: "PesuApp",
            dependencies: ["CSQLite"],
            path: "Sources/PesuApp"
        )
    ],
    swiftLanguageModes: [.v5]
)
