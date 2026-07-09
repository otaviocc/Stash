// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

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
            user.post("reset-totp", use: resetTOTP)
        }

        routes.get("stats", use: stats)

        let sessions = routes.grouped("sessions")
        sessions.get(use: listSessions)
        sessions.post("revoke-all", use: revokeAllSessions)
        sessions.post("revoke-user", use: revokeUserSessions)
    }

    func listUsers(req: Request) async throws -> [UserResponse] {
        let users = try await User.query(on: req.db).sort(\.$username).all()
        return try users.map { try $0.asResponse() }
    }

    func createUser(req: Request) async throws -> Response {
        let admin = try req.auth.require(User.self)
        try CreateUserInput.validate(content: req)
        let input = try req.content.decode(CreateUserInput.self)
        let username = input.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !username.isEmpty else {
            throw APIError.validationFailed("Username must not be empty.")
        }

        if try await userExists(username: username, on: req.db) {
            throw APIError.usernameTaken
        }

        let user = try await User(
            username: username,
            passwordHash: req.password.async.hash(input.password),
            role: .user
        )

        do {
            try await user.save(on: req.db)
        } catch {
            if try await userExists(username: username, on: req.db) {
                throw APIError.usernameTaken
            }
            throw error
        }

        await AuditLogger.record(
            action: "user_created",
            actor: admin.username,
            detail: "created user \(username)",
            ip: AuditLogger.clientIP(from: req),
            on: req.db
        )
        let response = Response(status: .created)
        try response.content.encode(user.asResponse())
        return response
    }

    func getUser(req: Request) async throws -> UserResponse {
        try await requireUser(req).asResponse()
    }

    func updateUser(req: Request) async throws -> UserResponse {
        let admin = try req.auth.require(User.self)
        let user = try await requireUser(req)
        let input = try req.content.decode(UpdateUserInput.self)

        var invalidateRefreshTokens = false
        var passwordChanged = false

        if let password = input.password {
            guard password.count >= 12 else {
                throw APIError.validationFailed("Password must be at least 12 characters.")
            }

            user.passwordHash = try await req.password.async.hash(password)
            invalidateRefreshTokens = true
            passwordChanged = true
        }

        var activeStateChanged = false

        if let isActive = input.isActive {
            if !isActive, try user.requireID() == admin.requireID() {
                throw APIError.cannotSuspendSelf
            }

            activeStateChanged = user.isActive != isActive
            user.isActive = isActive
            if !isActive {
                invalidateRefreshTokens = true
            }
        }

        try await user.save(on: req.db)
        if invalidateRefreshTokens {
            try await user.$refreshTokens.query(on: req.db).delete()
        }

        await AuditLogger.record(
            if: passwordChanged,
            action: "password_reset",
            actor: admin.username,
            detail: "reset password for \(user.username)",
            ip: AuditLogger.clientIP(from: req),
            on: req.db
        )
        if let isActive = input.isActive {
            await AuditLogger.record(
                if: activeStateChanged,
                action: isActive ? "user_unsuspended" : "user_suspended",
                actor: admin.username,
                detail: "\(isActive ? "unsuspended" : "suspended") \(user.username)",
                ip: AuditLogger.clientIP(from: req),
                on: req.db
            )
        }
        return try user.asResponse()
    }

    func deleteUser(req: Request) async throws -> Response {
        let admin = try req.auth.require(User.self)
        let user = try await requireUser(req)

        if try user.requireID() == admin.requireID() {
            throw APIError.cannotDeleteSelf
        }

        let deletedUsername = user.username

        try await user.$bookmarks.query(on: req.db).delete()
        try await user.$refreshTokens.query(on: req.db).delete()
        try await user.$recoveryCodes.query(on: req.db).delete()
        try await user.delete(on: req.db)

        await AuditLogger.record(
            action: "user_deleted",
            actor: admin.username,
            detail: "deleted user \(deletedUsername)",
            ip: AuditLogger.clientIP(from: req),
            on: req.db
        )

        return Response(status: .noContent)
    }

    func resetTOTP(req: Request) async throws -> Response {
        let admin = try req.auth.require(User.self)
        let user = try await requireUser(req)

        guard user.hasTOTPConfigured else {
            return Response(status: .noContent)
        }

        try await user.disableTOTP(on: req.db)

        await AuditLogger.record(
            action: "totp_reset",
            actor: admin.username,
            detail: "reset 2FA for \(user.username)",
            ip: AuditLogger.clientIP(from: req),
            on: req.db
        )

        return Response(status: .noContent)
    }

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

    // MARK: - Sessions

    func listSessions(req: Request) async throws -> SessionsListResponse {
        let rows = try await ActiveSessionLoader.loadActiveSessions(
            on: req,
            usernameQuery: req.query[String.self, at: "q"]
        )
        let responses = rows.map {
            SessionRowResponse(
                id: $0.id,
                userID: $0.userID,
                username: $0.username,
                sessionType: $0.sessionType.rawValue,
                userIsActive: $0.userIsActive
            )
        }
        return SessionsListResponse(sessions: responses, total: responses.count)
    }

    func revokeAllSessions(req: Request) async throws -> Response {
        let admin = try req.auth.require(User.self)

        _ = ActiveSessionLoader.revokeAll(on: req.application)
        try await RefreshToken.query(on: req.db).delete()

        await AuditLogger.record(
            action: "sessions_revoked_all",
            actor: admin.username,
            detail: "revoked all active sessions",
            ip: AuditLogger.clientIP(from: req),
            on: req.db
        )

        return Response(status: .noContent)
    }

    func revokeUserSessions(req: Request) async throws -> Response {
        let admin = try req.auth.require(User.self)
        try RevokeUserSessionsInput.validate(content: req)
        let input = try req.content.decode(RevokeUserSessionsInput.self)

        guard let user = try await User.query(on: req.db)
            .filter(\.$username == input.userName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            .first()
        else {
            throw APIError.notFound
        }

        let userID = try user.requireID()
        ActiveSessionLoader.revokeForUser(userID: userID, on: req.application)
        try await user.$refreshTokens.query(on: req.db).delete()

        await AuditLogger.record(
            action: "sessions_revoked_user",
            actor: admin.username,
            detail: "revoked sessions for \(user.username)",
            ip: AuditLogger.clientIP(from: req),
            on: req.db
        )

        return Response(status: .noContent)
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
