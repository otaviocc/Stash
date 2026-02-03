// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "stash",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(
            name: "stash",
            targets: ["stash"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(path: "../StashKit"),
        // Re-declared (StashKit's transitive dependency) so the CLI can build a custom
        // login NetworkRequest whose response covers the 2FA-challenge branch.
        .package(url: "https://github.com/otaviocc/MicroClient", from: "0.0.27")
    ],
    targets: [
        .executableTarget(
            name: "stash",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "StashKit", package: "StashKit"),
                .product(name: "MicroClient", package: "MicroClient")
            ]
        )
    ]
)
