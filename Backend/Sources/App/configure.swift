// MIT License
//
// Copyright (c) 2026 Otávio C.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Fluent
import FluentPostgresDriver
import FluentSQLiteDriver
import JWT
import Leaf
import Vapor

public func configure(_ app: Application) async throws {
    // MARK: Database

    if app.environment == .testing {
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

    // MARK: Passwords

    app.passwords.use(.bcrypt)

    // MARK: Migrations

    app.migrations.add(CreateUser())
    app.migrations.add(CreateRefreshToken())
    app.migrations.add(CreateRecoveryCode())
    app.migrations.add(CreateBookmark())
    app.migrations.add(CreateSiteSettings())
    app.migrations.add(CreateSmartViews())
    app.migrations.add(AddSmartViewMatchMode())
    app.migrations.add(CreateFaviconCache())

    // MARK: Version

    app.storage[AppVersionKey.self] = AppVersion.read(directory: app.directory.workingDirectory)

    // MARK: Outbound HTTP

    app.http.client.configuration.timeout = .init(connect: .seconds(5), read: .seconds(5))

    // MARK: Views

    app.views.use(.leaf)

    // MARK: Sessions

    app.sessions.use(.memory)
    app.sessions.configuration.cookieName = "stash_admin_session"

    // MARK: Error handling

    app.middleware = Middlewares()
    app.middleware.use(StashErrorMiddleware())

    // MARK: Static files

    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    // MARK: Routes

    try routes(app)

    // MARK: Migrations

    try await app.autoMigrate()

    // MARK: Site settings cache

    try await SiteSettingsService.loadAndCache(on: app)

    // MARK: First-boot admin seeding

    try await seedAdminIfNeeded(app)
}

/// Creates the admin account on first boot from `ADMIN_USERNAME` / `ADMIN_PASSWORD` (PRD §16).
/// Tests manage their own accounts, so seeding never runs against the in-memory test database.
private func seedAdminIfNeeded(_ app: Application) async throws {
    guard app.environment != .testing else { return }

    try await AdminSeeder.seed(
        username: Environment.get("ADMIN_USERNAME"),
        password: Environment.get("ADMIN_PASSWORD"),
        on: app.db,
        logger: app.logger
    ) { try await app.password.async.hash($0) }
}
