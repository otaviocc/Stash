import Fluent
import FluentPostgresDriver
import FluentSQLiteDriver
import JWT
import Leaf
import Vapor

public func configure(_ app: Application) async throws {
    // MARK: Database
    if app.environment == .testing {
        // Real in-memory SQLite for fast, isolated tests (PRD §17.7).
        app.databases.use(.sqlite(.memory), as: .sqlite)
    } else if let databaseURL = Environment.get("DATABASE_URL") {
        try app.databases.use(.postgres(url: databaseURL), as: .psql)
    } else {
        app.logger.critical("DATABASE_URL is not set.")
        throw APIError.custom(
            status: .internalServerError,
            code: "configuration_error",
            message: "DATABASE_URL is not set."
        )
    }

    // MARK: JWT
    let jwtSecret = Environment.get("JWT_SECRET")
        ?? (app.environment == .production ? "" : "dev-only-insecure-secret-change-me-please")
    if jwtSecret.isEmpty {
        app.logger.critical("JWT_SECRET is not set.")
        throw APIError.custom(
            status: .internalServerError,
            code: "configuration_error",
            message: "JWT_SECRET is not set."
        )
    }
    app.jwt.signers.use(.hs256(key: jwtSecret))

    // MARK: Passwords — bcrypt, cost factor 12 (PRD §8.5). Vapor's default cost is 12.
    app.passwords.use(.bcrypt)

    // MARK: Migrations
    app.migrations.add(CreateUser())
    app.migrations.add(CreateRefreshToken())
    app.migrations.add(CreateRecoveryCode())
    app.migrations.add(CreateBookmark())

    // MARK: Outbound HTTP — metadata fetching uses a 5s timeout, no retry (PRD §10).
    app.http.client.configuration.timeout = .init(connect: .seconds(5), read: .seconds(5))

    // MARK: Views (admin dashboard, from M5).
    app.views.use(.leaf)

    // MARK: Error handling — replace the default middleware with our envelope (PRD §17.4).
    app.middleware = Middlewares()
    app.middleware.use(StashErrorMiddleware())

    // MARK: Routes
    try routes(app)

    // Auto-migrate the throwaway test database.
    if app.environment == .testing {
        try await app.autoMigrate()
    }
}
