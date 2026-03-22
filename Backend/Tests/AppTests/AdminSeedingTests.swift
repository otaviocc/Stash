import Fluent
import Testing
import Vapor
import VaporTesting

@testable import App

@Suite("Admin seeding — first boot (PRD §16)")
struct AdminSeedingTests {
    // A hasher backed by the app's configured bcrypt.
    private func hasher(_ app: Application) -> (String) async throws -> String {
        { try await app.password.async.hash($0) }
    }

    @Test("seeds an admin when the database is empty")
    func seedsWhenEmpty() async throws {
        try await withTestApp { app in
            let created = try await AdminSeeder.seed(
                username: "Root", password: "admin-password-123",
                on: app.db, logger: app.logger, hash: hasher(app)
            )
            #expect(created == true)

            let admin = try await User.query(on: app.db).filter(\.$username == "root").first()
            #expect(admin?.role == .admin)
            #expect(admin?.isActive == true)

            // The seeded credentials actually work end-to-end.
            _ = try await app.login(username: "root", password: "admin-password-123")
        }
    }

    @Test("does nothing when a user already exists")
    func skipsWhenUsersExist() async throws {
        try await withTestApp { app in
            try await app.makeUser(username: "alice", password: "alice-password-123")

            let created = try await AdminSeeder.seed(
                username: "root", password: "admin-password-123",
                on: app.db, logger: app.logger, hash: hasher(app)
            )
            #expect(created == false)
            let root = try await User.query(on: app.db).filter(\.$username == "root").first()
            #expect(root == nil)
        }
    }

    @Test("throws when no user exists and credentials are missing")
    func throwsWhenMissingCredentials() async throws {
        try await withTestApp { app in
            var thrown: Error?
            do {
                _ = try await AdminSeeder.seed(
                    username: nil, password: nil,
                    on: app.db, logger: app.logger, hash: hasher(app)
                )
            } catch {
                thrown = error
            }
            #expect(thrown != nil)
            // Nothing was created.
            let count = try await User.query(on: app.db).count()
            #expect(count == 0)
        }
    }

    @Test("throws when the admin password is shorter than 12 characters")
    func throwsWhenPasswordTooShort() async throws {
        try await withTestApp { app in
            var thrown: Error?
            do {
                _ = try await AdminSeeder.seed(
                    username: "root", password: "short",
                    on: app.db, logger: app.logger, hash: hasher(app)
                )
            } catch {
                thrown = error
            }
            #expect(thrown != nil)
            let count = try await User.query(on: app.db).count()
            #expect(count == 0)
        }
    }
}
