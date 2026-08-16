// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "StashKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "StashKit",
            targets: ["StashKit"]
        )
    ],
    dependencies: [
        // Typed networking layer (NetworkRequest / NetworkClient / interceptors).
        .package(url: "https://github.com/otaviocc/MicroClient", from: "0.0.28")
    ],
    targets: [
        .target(
            name: "StashKit",
            dependencies: [
                .product(name: "MicroClient", package: "MicroClient")
            ]
        ),
        .testTarget(
            name: "StashKitTests",
            dependencies: [
                .target(name: "StashKit"),
                .product(name: "MicroClient", package: "MicroClient")
            ]
        )
    ]
)
