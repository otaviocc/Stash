// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "stash",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // Web framework
        .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
        // ORM
        .package(url: "https://github.com/vapor/fluent.git", from: "4.0.0"),
        // PostgreSQL driver (production)
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.0.0"),
        // SQLite driver (in-memory test database — see PRD §17.7)
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.0.0"),
        // JWT signing + verification
        .package(url: "https://github.com/vapor/jwt.git", from: "4.0.0"),
        // Server-rendered HTML (admin dashboard — used from M5 onward)
        .package(url: "https://github.com/vapor/leaf.git", from: "4.0.0")
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "JWT", package: "jwt"),
                .product(name: "Leaf", package: "leaf")
            ],
            path: "Sources/App",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "VaporTesting", package: "vapor")
            ],
            path: "Tests/AppTests",
            swiftSettings: swiftSettings
        )
    ]
)

var swiftSettings: [SwiftSetting] {
    [
        .enableUpcomingFeature("DisableOutwardActorInference")
    ]
}
