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

/// Authenticated endpoints for the current user (PRD §9.2).
struct UserController: RouteCollection {

    func boot(routes: RoutesBuilder) throws {
        routes.get("me", use: me)
        routes.put("me", "password", use: changePassword)

        let totp = routes.grouped("auth", "totp")
        totp.get("setup", use: setupTOTP)
        totp.post("verify-setup", use: verifyTOTPSetup)
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
}
