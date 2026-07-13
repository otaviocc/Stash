// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

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
    app.migrations.add(CreateDeletedBookmarks())
    app.migrations.add(CreateAuditLog())
    app.migrations.add(AddBookmarkWayback())
    app.migrations.add(AddSiteSettingsInternetArchive())
    app.migrations.add(AddUserArchiveNewBookmarks())
    app.migrations.add(AddBookmarkWaybackRetryCount())
    app.migrations.add(AddSiteSettingsUpdateCheck())

    // MARK: Version

    app.storage[AppVersionKey.self] = AppVersion.read(directory: app.directory.workingDirectory)

    // MARK: Boot time

    app.storage[BootDateKey.self] = Date()

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

    // MARK: Internet Archive submission queue

    await WaybackSubmitter.bootstrap(on: app)

    // MARK: Update checker

    UpdateChecker.bootstrap(on: app)

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
