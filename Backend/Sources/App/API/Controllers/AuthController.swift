// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import JWT
import Vapor

/// Unauthenticated auth endpoints (PRD §9.1).
struct AuthController: RouteCollection {

    // MARK: Static Functions

    // MARK: - Helpers

    private static func userFromTempToken(_ token: String, req: Request) async throws -> User {
        let payload: TempTokenPayload
        do {
            payload = try req.jwt.verify(token, as: TempTokenPayload.self)
        } catch {
            throw APIError.tokenInvalid
        }
        guard let userID = payload.userID,
              let user = try await User.find(userID, on: req.db)
        else {
            throw APIError.tokenInvalid
        }
        guard user.isActive else { throw APIError.accountSuspended }

        return user
    }

    // MARK: Functions

    func boot(routes: RoutesBuilder) throws {
        let auth = routes.grouped("auth")
        auth.post("login", use: login)
        auth.post("totp", use: totp)
        auth.post("recovery", use: recovery)
        auth.post("refresh", use: refresh)
        auth.post("logout", use: logout)
    }

    func login(req: Request) async throws -> Response {
        try LoginRequest.validate(content: req)
        let input = try req.content.decode(LoginRequest.self)

        guard let user = try await User.query(on: req.db)
            .filter(\.$username == input.username.lowercased())
            .first()
        else {
            _ = try? await req.password.async.verify(input.password, created: User.dummyPasswordHash)
            await AuditLogger.record(
                action: "login_failure",
                actor: input.username.lowercased(),
                detail: "unknown username",
                ip: AuditLogger.clientIP(from: req),
                on: req.db
            )
            throw APIError.invalidCredentials
        }
        guard try await req.password.async.verify(input.password, created: user.passwordHash) else {
            await AuditLogger.record(
                action: "login_failure",
                actor: user.username,
                detail: "wrong password",
                ip: AuditLogger.clientIP(from: req),
                on: req.db
            )
            throw APIError.invalidCredentials
        }
        guard user.isActive else {
            await AuditLogger.record(
                action: "login_failure",
                actor: user.username,
                detail: "account suspended",
                ip: AuditLogger.clientIP(from: req),
                on: req.db
            )
            throw APIError.accountSuspended
        }

        if user.isTOTPEnabled {
            let tempToken = try req.jwt.sign(TempTokenPayload(user: user))
            return try await TwoFactorRequired(tempToken: tempToken).encodeResponse(for: req)
        }

        await AuditLogger.record(
            action: "login_success",
            actor: user.username,
            detail: "api login",
            ip: AuditLogger.clientIP(from: req),
            on: req.db
        )
        let pair = try await TokenService.issuePair(for: user, on: req)
        return try await pair.encodeResponse(for: req)
    }

    func totp(req: Request) async throws -> TokenPair {
        let input = try req.content.decode(TOTPRequest.self)
        let user = try await Self.userFromTempToken(input.tempToken, req: req)

        guard let secret = user.totpSecret, user.isTOTPEnabled,
              let secretData = Base32.decode(secret),
              TOTP(secret: secretData).validate(input.totpCode)
        else {
            await AuditLogger.record(
                action: "login_failure",
                actor: user.username,
                detail: "invalid TOTP code",
                ip: AuditLogger.clientIP(from: req),
                on: req.db
            )
            throw APIError.totpInvalid
        }

        await AuditLogger.record(
            action: "login_success",
            actor: user.username,
            detail: "api totp",
            ip: AuditLogger.clientIP(from: req),
            on: req.db
        )

        return try await TokenService.issuePair(for: user, on: req)
    }

    func recovery(req: Request) async throws -> TokenPair {
        let input = try req.content.decode(RecoveryRequest.self)
        let user = try await Self.userFromTempToken(input.tempToken, req: req)

        let normalized = RecoveryCodes.normalize(input.recoveryCode)
        let codes = try await user.$recoveryCodes.query(on: req.db)
            .filter(\.$usedAt == nil)
            .all()

        for code in codes {
            // swiftlint:disable:next for_where - async predicate; a `where` clause can't hold `try await`.
            if try await req.password.async.verify(normalized, created: code.codeHash) {
                code.usedAt = Date()
                try await code.save(on: req.db)
                await AuditLogger.record(
                    action: "login_success",
                    actor: user.username,
                    detail: "via recovery code",
                    ip: AuditLogger.clientIP(from: req),
                    on: req.db
                )

                return try await TokenService.issuePair(for: user, on: req)
            }
        }
        await AuditLogger.record(
            action: "login_failure",
            actor: user.username,
            detail: "invalid recovery code",
            ip: AuditLogger.clientIP(from: req),
            on: req.db
        )
        throw APIError.totpInvalid
    }

    func refresh(req: Request) async throws -> TokenPair {
        let input = try req.content.decode(RefreshRequest.self)
        let tokenHash = TokenService.hash(input.refreshToken)

        guard let stored = try await RefreshToken.query(on: req.db)
            .filter(\.$tokenHash == tokenHash)
            .first()
        else {
            throw APIError.tokenInvalid
        }
        guard stored.expiresAt > Date() else {
            try await stored.delete(on: req.db)
            throw APIError.tokenExpired
        }
        guard let user = try await User.find(stored.$user.id, on: req.db), user.isActive else {
            try await stored.delete(on: req.db)
            throw APIError.tokenInvalid
        }

        try await stored.delete(on: req.db)
        return try await TokenService.issuePair(for: user, on: req)
    }

    func logout(req: Request) async throws -> Response {
        let input = try req.content.decode(LogoutRequest.self)
        let tokenHash = TokenService.hash(input.refreshToken)

        let stored = try await RefreshToken.query(on: req.db)
            .filter(\.$tokenHash == tokenHash)
            .first()
        var actor: String?
        if let stored {
            actor = try await User.find(stored.$user.id, on: req.db)?.username
        }

        try await RefreshToken.query(on: req.db)
            .filter(\.$tokenHash == tokenHash)
            .delete()

        await AuditLogger.record(
            action: "logout",
            actor: actor,
            ip: AuditLogger.clientIP(from: req),
            on: req.db
        )

        return Response(status: .noContent)
    }
}
