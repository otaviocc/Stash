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

    // GET /me
    func me(req: Request) async throws -> UserResponse {
        let user = try req.auth.require(User.self)
        return try user.asResponse()
    }

    // PUT /me/password
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

    // GET /auth/totp/setup — begin enrolment (PRD §8.3).
    func setupTOTP(req: Request) async throws -> TOTPSetupResponse {
        let user = try req.auth.require(User.self)

        // Generate (or regenerate, if not yet confirmed) a secret and persist it.
        let secret = TOTP.generateSecret()
        user.totpSecret = secret
        try await user.save(on: req.db)

        return TOTPSetupResponse(
            secret: secret,
            otpauthURI: TOTP.otpauthURI(secret: secret, username: user.username)
        )
    }

    // POST /auth/totp/verify-setup — confirm enrolment, return recovery codes once (PRD §8.3).
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

        // Replace any prior recovery codes, then enable 2FA.
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
