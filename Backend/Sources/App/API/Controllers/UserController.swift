// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Vapor

/// Authenticated endpoints for the current user (Docs/product-api.md §9.2).
struct UserController: RouteCollection {

    func boot(routes: RoutesBuilder) throws {
        routes.get("me", use: me)
        routes.put("me", "password", use: changePassword)

        let totp = routes.grouped("auth", "totp")
        totp.get("setup", use: setupTOTP)
        totp.post("verify-setup", use: verifyTOTPSetup)
        totp.post("disable", use: disableTOTP)
    }

    func me(req: Request) async throws -> UserResponse {
        let user = try req.auth.require(User.self)
        return try user.asResponse()
    }

    func changePassword(req: Request) async throws -> Response {
        try ChangePasswordRequest.validate(content: req)
        let input = try req.content.decode(ChangePasswordRequest.self)
        let user = try req.auth.require(User.self)

        guard try await req.password.async.verify(input.currentPassword, created: user.passwordHash) else {
            throw APIError.invalidCredentials
        }

        user.passwordHash = try await req.password.async.hash(input.newPassword)
        try await user.save(on: req.db)
        return Response(status: .noContent)
    }

    func setupTOTP(req: Request) async throws -> TOTPSetupResponse {
        let user = try req.auth.require(User.self)

        let secret = TOTP.generateSecret()
        user.totpSecret = secret
        try await user.save(on: req.db)

        return TOTPSetupResponse(
            secret: secret,
            otpauthURI: TOTP.otpauthURI(secret: secret, username: user.username)
        )
    }

    func verifyTOTPSetup(req: Request) async throws -> RecoveryCodesResponse {
        let input = try req.content.decode(VerifySetupRequest.self)
        let user = try req.auth.require(User.self)

        guard let secret = user.totpSecret, let secretData = Base32.decode(secret) else {
            throw APIError.custom(
                status: .badRequest,
                code: "totp_setup_required",
                message: "Call /auth/totp/setup before verifying."
            )
        }
        guard TOTP(secret: secretData).validate(input.totpCode) else {
            throw APIError.totpInvalid
        }

        try await user.$recoveryCodes.query(on: req.db).delete()

        let plainCodes = RecoveryCodes.generate()
        for code in plainCodes {
            let hash = try await req.password.async.hash(RecoveryCodes.normalize(code))
            try await RecoveryCode(userID: user.requireID(), codeHash: hash).save(on: req.db)
        }

        user.isTOTPEnabled = true
        try await user.save(on: req.db)

        return RecoveryCodesResponse(recoveryCodes: plainCodes)
    }

    func disableTOTP(req: Request) async throws -> Response {
        let input = try req.content.decode(DisableTOTPRequest.self)
        let user = try req.auth.require(User.self)

        guard user.isTOTPEnabled, let secret = user.totpSecret, let secretData = Base32.decode(secret),
              TOTP(secret: secretData).validate(input.totpCode)
        else {
            throw APIError.totpInvalid
        }

        try await user.disableTOTP(on: req.db)
        return Response(status: .noContent)
    }
}
