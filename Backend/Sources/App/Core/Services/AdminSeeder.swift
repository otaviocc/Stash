// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Vapor

/// First-boot admin account seeding (PRD §16).
enum AdminSeeder {

    @discardableResult
    static func seed(
        username rawUsername: String?,
        password: String?,
        on db: Database,
        logger: Logger,
        hash: (String) async throws -> String
    ) async throws -> Bool {
        let userCount = try await User.query(on: db).count()
        guard userCount == 0 else {
            return false
        }
        guard let username = rawUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
              let password,
              !username.isEmpty, !password.isEmpty
        else {
            logger.critical(
                "No users exist and ADMIN_USERNAME / ADMIN_PASSWORD are not both set. Cannot create the admin account. Set both environment variables and restart."
            )
            throw Abort(
                .internalServerError,
                reason: "Missing ADMIN_USERNAME / ADMIN_PASSWORD for first-boot admin seeding."
            )
        }
        guard password.count >= 12 else {
            logger.critical("ADMIN_PASSWORD must be at least 12 characters. The admin account was not created.")
            throw Abort(.internalServerError, reason: "ADMIN_PASSWORD must be at least 12 characters.")
        }

        let admin = try await User(username: username, passwordHash: hash(password), role: .admin)
        try await admin.save(on: db)
        logger.notice("First boot: created admin account '\(admin.username)'.")
        return true
    }
}
