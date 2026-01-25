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
import Testing
import Vapor
import VaporTesting
@testable import App

/// Verifies the first-boot admin seeding behavior.
@Suite("Admin seeding — first boot (PRD §16)")
struct AdminSeedingTests {

    @Test("seeds an admin when the database is empty")
    func seedsWhenEmpty() async throws {
        try await withTestApp { app in
            // Given — no setup required

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
            // Given — no setup required

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
            // Given — no setup required

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
