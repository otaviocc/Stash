import Fluent
import Vapor

/// Admin user-management API, admin role only (PRD §9.6). Mounted under `/admin`, behind
/// `AdminMiddleware`.
struct AdminController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let users = routes.grouped("users")
        users.get(use: listUsers)
        users.post(use: createUser)
        users.group(":userID") { user in
            user.get(use: getUser)
            user.put(use: updateUser)
            user.delete(use: deleteUser)
        }

        routes.get("stats", use: stats)
    }

    // GET /admin/users — all users with their stats.
    func listUsers(req: Request) async throws -> [UserResponse] {
        let users = try await User.query(on: req.db).sort(\.$username).all()
        return try users.map { try $0.asResponse() }
    }

    // POST /admin/users — create a new account.
    func createUser(req: Request) async throws -> Response {
        try CreateUserInput.validate(content: req)
        let input = try req.content.decode(CreateUserInput.self)
        let username = input.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !username.isEmpty else {
            throw APIError.validationFailed("Username must not be empty.")
        }
        if try await self.userExists(username: username, on: req.db) {
            throw APIError.usernameTaken
        }

        // Always created as a regular user; admins only exist via first-boot seeding (PRD §4).
        let user = User(
            username: username,
            passwordHash: try await req.password.async.hash(input.password),
            role: .user
        )

        do {
            try await user.save(on: req.db)
        } catch {
            // Unique-index backstop for a race between the check above and the insert.
            if try await self.userExists(username: username, on: req.db) {
                throw APIError.usernameTaken
            }
            throw error
        }

        let response = Response(status: .created)
        try response.content.encode(try user.asResponse())
        return response
    }

    // GET /admin/users/:id
    func getUser(req: Request) async throws -> UserResponse {
        try await self.requireUser(req).asResponse()
    }

    // PUT /admin/users/:id — suspend/unsuspend and/or reset password.
    func updateUser(req: Request) async throws -> UserResponse {
        let user = try await self.requireUser(req)
        let input = try req.content.decode(UpdateUserInput.self)

        var invalidateRefreshTokens = false

        if let password = input.password {
            guard password.count >= 12 else {
                throw APIError.validationFailed("Password must be at least 12 characters.")
            }
            user.passwordHash = try await req.password.async.hash(password)
            // A password reset forces re-authentication everywhere (same as suspension).
            invalidateRefreshTokens = true
        }

        if let isActive = input.isActive {
            user.isActive = isActive
            if !isActive {
                // Suspension: immediately invalidate all refresh tokens (PRD §8.6).
                invalidateRefreshTokens = true
            }
        }

        try await user.save(on: req.db)
        if invalidateRefreshTokens {
            try await user.$refreshTokens.query(on: req.db).delete()
        }
        return try user.asResponse()
    }

    // DELETE /admin/users/:id — hard delete, cascading all owned data (PRD §8.6).
    func deleteUser(req: Request) async throws -> Response {
        let admin = try req.auth.require(User.self)
        let user = try await self.requireUser(req)

        // An admin cannot delete their own account.
        if try user.requireID() == admin.requireID() {
            throw APIError.cannotDeleteSelf
        }

        // Explicit cascade so the behaviour holds on SQLite (tests) as well as Postgres,
        // regardless of FK enforcement.
        try await user.$bookmarks.query(on: req.db).delete()
        try await user.$refreshTokens.query(on: req.db).delete()
        try await user.$recoveryCodes.query(on: req.db).delete()
        try await user.delete(on: req.db)

        return Response(status: .noContent)
    }

    // GET /admin/stats — aggregate stats with per-user bookmark counts.
    func stats(req: Request) async throws -> AdminStatsResponse {
        let users = try await User.query(on: req.db).sort(\.$username).all()
        let userStats = try users.map { user in
            UserStat(
                id: try user.requireID(),
                username: user.username,
                bookmarkCount: user.bookmarkCount,
                isActive: user.isActive
            )
        }
        let totalBookmarks = userStats.reduce(0) { $0 + $1.bookmarkCount }
        return AdminStatsResponse(
            totalUsers: users.count,
            totalBookmarks: totalBookmarks,
            users: userStats
        )
    }

    // MARK: - Helpers

    private func requireUser(_ req: Request) async throws -> User {
        guard let id = req.parameters.get("userID", as: UUID.self),
              let user = try await User.find(id, on: req.db) else {
            throw APIError.notFound
        }
        return user
    }

    private func userExists(username: String, on db: Database) async throws -> Bool {
        try await User.query(on: db).filter(\.$username == username).first() != nil
    }
}
