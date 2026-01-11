import Fluent
import Vapor

/// First-boot admin account seeding (PRD §16).
enum AdminSeeder {
    /// Create the admin account when the database has no users yet.
    ///
    /// - Returns: `true` if an admin was created, `false` if seeding was skipped because a
    ///   user already exists (the env vars are ignored from then on).
    /// - Throws: when no user exists but the credentials are missing or invalid — the caller
    ///   should let this propagate so the process exits rather than starting a broken,
    ///   login-less instance.
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
            throw Abort(.internalServerError, reason: "Missing ADMIN_USERNAME / ADMIN_PASSWORD for first-boot admin seeding.")
        }

        // Enforce the password rule (min 12 characters, PRD §8.5) before creating the account.
        guard password.count >= 12 else {
            logger.critical("ADMIN_PASSWORD must be at least 12 characters. The admin account was not created.")
            throw Abort(.internalServerError, reason: "ADMIN_PASSWORD must be at least 12 characters.")
        }

        let admin = User(username: username, passwordHash: try await hash(password), role: .admin)
        try await admin.save(on: db)
        logger.notice("First boot: created admin account '\(admin.username)'.")
        return true
    }
}
