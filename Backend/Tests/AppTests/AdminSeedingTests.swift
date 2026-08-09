// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Testing
import Vapor
import VaporTesting
@testable import App

/// Verifies the first-boot admin seeding behavior.
@Suite("Admin seeding, first boot (Docs/product-deployment.md §18)")
struct AdminSeedingTests {

    @Test("seeds an admin when the database is empty")
    func seedsWhenEmpty() async throws {
        try await withTestApp { app in
            // Given: no setup required

            // When
            let created = try await AdminSeeder.seed(
                username: "Root", password: "admin-password-123",
                on: app.db, logger: app.logger, hash: hasher(app)
            )

            // Then
            #expect(created == true, "It should report that an admin was created")

            let admin = try await User.query(on: app.db).filter(\.$username == "root").first()
            #expect(admin?.role == .admin, "It should seed the account with the admin role")
            #expect(admin?.isActive == true, "It should seed the account as active")

            _ = try await app.login(username: "root", password: "admin-password-123")
        }
    }

    @Test("does nothing when a user already exists")
    func skipsWhenUsersExist() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "alice", password: "alice-password-123")

            // When
            let created = try await AdminSeeder.seed(
                username: "root", password: "admin-password-123",
                on: app.db, logger: app.logger, hash: hasher(app)
            )

            // Then
            #expect(created == false, "It should report that no admin was created")
            let root = try await User.query(on: app.db).filter(\.$username == "root").first()
            #expect(root == nil, "It should not create the root account")
        }
    }

    @Test("throws when no user exists and credentials are missing")
    func throwsWhenMissingCredentials() async throws {
        try await withTestApp { app in
            // Given: no setup required

            // When
            var thrown: Error?
            do {
                _ = try await AdminSeeder.seed(
                    username: nil, password: nil,
                    on: app.db, logger: app.logger, hash: hasher(app)
                )
            } catch {
                thrown = error
            }

            // Then
            #expect(thrown != nil, "It should throw when credentials are missing")
            let count = try await User.query(on: app.db).count()
            #expect(count == 0, "It should not create any user")
        }
    }

    @Test("throws when the admin password is shorter than 12 characters")
    func throwsWhenPasswordTooShort() async throws {
        try await withTestApp { app in
            // Given: no setup required

            // When
            var thrown: Error?
            do {
                _ = try await AdminSeeder.seed(
                    username: "root", password: "short",
                    on: app.db, logger: app.logger, hash: hasher(app)
                )
            } catch {
                thrown = error
            }

            // Then
            #expect(thrown != nil, "It should throw when the password is too short")
            let count = try await User.query(on: app.db).count()
            #expect(count == 0, "It should not create any user")
        }
    }

    private func hasher(_ app: Application) -> (String) async throws -> String {
        { try await app.password.async.hash($0) }
    }
}
