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

    /// GET /admin/users — all users with their stats.
    func listUsers(req: Request) async throws -> [UserResponse] {
        let users = try await User.query(on: req.db).sort(\.$username).all()
        return try users.map { try $0.asResponse() }
    }

    /// POST /admin/users — create a new account.
    func createUser(req: Request) async throws -> Response {
        try CreateUserInput.validate(content: req)
        let input = try req.content.decode(CreateUserInput.self)
        let username = input.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !username.isEmpty else {
            throw APIError.validationFailed("Username must not be empty.")
        }
        if try await userExists(username: username, on: req.db) {
            throw APIError.usernameTaken
        }

        // Always created as a regular user; admins only exist via first-boot seeding (PRD §4).
        let user = try await User(
            username: username,
            passwordHash: req.password.async.hash(input.password),
            role: .user
        )

        do {
            try await user.save(on: req.db)
        } catch {
            // Unique-index backstop for a race between the check above and the insert.
            if try await userExists(username: username, on: req.db) {
                throw APIError.usernameTaken
            }
            throw error
        }

        let response = Response(status: .created)
        try response.content.encode(user.asResponse())
        return response
    }

    /// GET /admin/users/:id
    func getUser(req: Request) async throws -> UserResponse {
        try await requireUser(req).asResponse()
    }

    /// PUT /admin/users/:id — suspend/unsuspend and/or reset password.
    func updateUser(req: Request) async throws -> UserResponse {
        let user = try await requireUser(req)
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

    /// DELETE /admin/users/:id — hard delete, cascading all owned data (PRD §8.6).
    func deleteUser(req: Request) async throws -> Response {
        let admin = try req.auth.require(User.self)
        let user = try await requireUser(req)

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

    /// GET /admin/stats — aggregate stats with per-user bookmark counts.
    func stats(req: Request) async throws -> AdminStatsResponse {
        let users = try await User.query(on: req.db).sort(\.$username).all()
        let userStats = try users.map { user in
            try UserStat(
                id: user.requireID(),
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
              let user = try await User.find(id, on: req.db)
        else {
            throw APIError.notFound
        }
        return user
    }

    private func userExists(username: String, on db: Database) async throws -> Bool {
        try await User.query(on: db).filter(\.$username == username).first() != nil
    }
}
