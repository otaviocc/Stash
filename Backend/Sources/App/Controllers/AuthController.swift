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
import JWT
import Vapor

/// Unauthenticated auth endpoints (PRD §9.1).
struct AuthController: RouteCollection {

    // MARK: Static Properties

    private static let dummyHash =
        "$2b$12$C6UzMDM.H6dfI/f/IKcEeO2x0jXJ8nKqK8h0V2vQ1nC3l6mFqKQ4u"

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
            _ = try? await req.password.async.verify(input.password, created: Self.dummyHash)
            throw APIError.invalidCredentials
        }
        guard try await req.password.async.verify(input.password, created: user.passwordHash) else {
            throw APIError.invalidCredentials
        }
        guard user.isActive else {
            throw APIError.accountSuspended
        }

        if user.isTOTPEnabled {
            let tempToken = try req.jwt.sign(TempTokenPayload(user: user))
            return try await TwoFactorRequired(tempToken: tempToken).encodeResponse(for: req)
        }

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
            throw APIError.totpInvalid
        }

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
                return try await TokenService.issuePair(for: user, on: req)
            }
        }
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
        try await RefreshToken.query(on: req.db)
            .filter(\.$tokenHash == tokenHash)
            .delete()
        return Response(status: .noContent)
    }
}
