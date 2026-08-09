// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Testing
import VaporTesting
@testable import App

/// Covers TOTP-based two-factor enrollment, login, and recovery-code flows.
@Suite("Auth: TOTP 2FA enrollment and login")
struct TwoFactorTests {

    @Test("enrollment returns 8 recovery codes and enables 2FA")
    func enrollment() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            // When
            let (_, codes) = try await enrol(app, accessToken: pair.accessToken)

            // Then
            #expect(codes.count == 8, "It should return eight recovery codes")
            #expect(codes.allSatisfy { $0.contains("-") }, "It should format each recovery code with a dash")

            try await app.testing().test(
                .POST, "api/v1/auth/login",
                beforeRequest: { req in
                    try req.content.encode(LoginRequest(username: "otavio", password: "correct-horse-battery"))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .ok, "It should return 200 OK")
                    let challenge = try res.content.decode(TwoFactorRequired.self)
                    #expect(challenge.requires2FA == true, "It should require 2FA after enrollment")
                    #expect(!challenge.tempToken.isEmpty, "It should issue a non-empty temp token")
                }
            )
        }
    }

    @Test("verify-setup with a wrong code is rejected")
    func verifySetupWrongCode() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await app.testing().test(
                .GET, "api/v1/auth/totp/setup",
                headers: ["Authorization": "Bearer \(pair.accessToken)"]
            ) { res async throws in #expect(res.status == .ok, "It should return 200 OK") }

            // When
            try await app.testing().test(
                .POST, "api/v1/auth/totp/verify-setup",
                headers: ["Authorization": "Bearer \(pair.accessToken)"],
                beforeRequest: { req in
                    try req.content.encode(VerifySetupRequest(totpCode: "000000"))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .unauthorized, "It should return 401 Unauthorized")
                    let err = try res.content.decode(TestError.self)
                    #expect(err.code == "totp_invalid", "It should return the totp_invalid code")
                }
            )
        }
    }

    @Test("full 2FA login flow: tempToken + valid TOTP code yields a token pair")
    func totpLogin() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let (secret, _) = try await enrol(app, accessToken: pair.accessToken)
            let tempToken = try await app.loginForTempToken(username: "otavio", password: "correct-horse-battery")
            let code = TOTP(secret: Base32.decode(secret)!).generate()

            // When
            try await app.testing().test(
                .POST, "api/v1/auth/totp",
                beforeRequest: { req in
                    try req.content.encode(TOTPRequest(tempToken: tempToken, totpCode: code))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .ok, "It should return 200 OK")
                    let tokens = try res.content.decode(TokenPair.self)
                    #expect(!tokens.accessToken.isEmpty, "It should issue a non-empty access token")
                    #expect(!tokens.refreshToken.isEmpty, "It should issue a non-empty refresh token")
                }
            )
        }
    }

    @Test("wrong TOTP code after login is rejected")
    func totpLoginWrongCode() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            _ = try await enrol(app, accessToken: pair.accessToken)
            let tempToken = try await app.loginForTempToken(username: "otavio", password: "correct-horse-battery")

            // When
            try await app.testing().test(
                .POST, "api/v1/auth/totp",
                beforeRequest: { req in
                    try req.content.encode(TOTPRequest(tempToken: tempToken, totpCode: "000000"))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .unauthorized, "It should return 401 Unauthorized")
                    let err = try res.content.decode(TestError.self)
                    #expect(err.code == "totp_invalid", "It should return the totp_invalid code")
                }
            )
        }
    }

    @Test("recovery code redeems once and cannot be reused")
    func recoveryCodeSingleUse() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let (_, codes) = try await enrol(app, accessToken: pair.accessToken)
            let recoveryCode = codes[0]

            // When
            let tempToken1 = try await app.loginForTempToken(username: "otavio", password: "correct-horse-battery")
            try await app.testing().test(
                .POST, "api/v1/auth/recovery",
                beforeRequest: { req in
                    try req.content.encode(RecoveryRequest(tempToken: tempToken1, recoveryCode: recoveryCode))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .ok, "It should accept the recovery code on first use")
                    _ = try res.content.decode(TokenPair.self)
                }
            )

            let tempToken2 = try await app.loginForTempToken(username: "otavio", password: "correct-horse-battery")
            try await app.testing().test(
                .POST, "api/v1/auth/recovery",
                beforeRequest: { req in
                    try req.content.encode(RecoveryRequest(tempToken: tempToken2, recoveryCode: recoveryCode))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unauthorized, "It should reject the recovery code on reuse")
                    let err = try res.content.decode(TestError.self)
                    #expect(err.code == "totp_invalid", "It should return the totp_invalid code")
                }
            )
        }
    }

    @Test("totp endpoint rejects a malformed temp token")
    func totpBadTempToken() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")

            // When
            try await app.testing().test(
                .POST, "api/v1/auth/totp",
                beforeRequest: { req in
                    try req.content.encode(TOTPRequest(tempToken: "not-a-jwt", totpCode: "123456"))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .unauthorized, "It should return 401 Unauthorized")
                    let err = try res.content.decode(TestError.self)
                    #expect(err.code == "token_invalid", "It should return the token_invalid code")
                }
            )
        }
    }

    @Test("disable with a valid code turns 2FA off, clears recovery codes, and revokes sessions")
    func disableSucceeds() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let (secret, _) = try await enrol(app, accessToken: pair.accessToken)
            let code = TOTP(secret: Base32.decode(secret)!).generate()

            // When
            try await app.testing().test(
                .POST, "api/v1/auth/totp/disable",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(DisableTOTPRequest(totpCode: code))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .noContent, "It should return 204 No Content")
                }
            )

            let reloaded = try await User.find(user.requireID(), on: app.db)
            #expect(reloaded?.isTOTPEnabled == false, "It should disable 2FA")
            #expect(reloaded?.totpSecret == nil, "It should clear the TOTP secret")

            let codeCount = try await reloaded!.$recoveryCodes.query(on: app.db).count()
            #expect(codeCount == 0, "It should delete the recovery codes")

            let tokenCount = try await reloaded!.$refreshTokens.query(on: app.db).count()
            #expect(tokenCount == 0, "It should revoke all refresh tokens")
        }
    }

    @Test("disable with a wrong code is rejected and leaves 2FA enabled")
    func disableWrongCode() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            _ = try await enrol(app, accessToken: pair.accessToken)

            // When
            try await app.testing().test(
                .POST, "api/v1/auth/totp/disable",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(DisableTOTPRequest(totpCode: "000000"))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .unauthorized, "It should return 401 Unauthorized")
                    let err = try res.content.decode(TestError.self)
                    #expect(err.code == "totp_invalid", "It should return the totp_invalid code")
                }
            )

            let reloaded = try await User.find(user.requireID(), on: app.db)
            #expect(reloaded?.isTOTPEnabled == true, "It should leave 2FA enabled")
        }
    }

    @Test("disable is rejected when 2FA is not enabled")
    func disableWhenNotEnabled() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            // When
            try await app.testing().test(
                .POST, "api/v1/auth/totp/disable",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(DisableTOTPRequest(totpCode: "000000"))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .unauthorized, "It should return 401 Unauthorized")
                    let err = try res.content.decode(TestError.self)
                    #expect(err.code == "totp_invalid", "It should return the totp_invalid code")
                }
            )
        }
    }

    @Test("disable requires authentication")
    func disableUnauthenticated() async throws {
        try await withTestApp { app in
            // Given: no token

            // When
            try await app.testing().test(
                .POST, "api/v1/auth/totp/disable",
                beforeRequest: { req in
                    try req.content.encode(DisableTOTPRequest(totpCode: "123456"))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .unauthorized, "It should return 401 Unauthorized")
                }
            )
        }
    }

    // MARK: - Audit log

    @Test("2FA-enabled login only writes login_success after totp succeeds, not at the initial login call")
    func jsonLoginWithTOTPAuditedOnlyAfterTOTP() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let (secret, _) = try await enrol(app, accessToken: pair.accessToken)

            // When
            let tempToken = try await app.loginForTempToken(username: "otavio", password: "correct-horse-battery")
            let rowsAfterLogin = try await AuditLog.query(on: app.db).all()
            let successesAfterLogin = rowsAfterLogin.filter { $0.action == "login_success" }.count

            let code = TOTP(secret: Base32.decode(secret)!).generate()
            try await app.testing().test(
                .POST, "api/v1/auth/totp",
                beforeRequest: { req in
                    try req.content.encode(TOTPRequest(tempToken: tempToken, totpCode: code))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .ok, "It should return 200 OK")
                }
            )

            // Then
            let rows = try await AuditLog.query(on: app.db).all()
            let successesAfterTOTP = rows.filter { $0.action == "login_success" }.count
            #expect(
                successesAfterTOTP == successesAfterLogin + 1,
                "It should record login_success only once the TOTP step completes, not at the initial login call"
            )
        }
    }

    @Test("recovery-code login writes a login_success row, and a bad recovery code writes login_failure")
    func recoveryLoginAudited() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let (_, codes) = try await enrol(app, accessToken: pair.accessToken)

            // When
            let badTempToken = try await app.loginForTempToken(username: "otavio", password: "correct-horse-battery")
            try await app.testing().test(
                .POST, "api/v1/auth/recovery",
                beforeRequest: { req in
                    try req.content.encode(RecoveryRequest(tempToken: badTempToken, recoveryCode: "0000-0000"))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unauthorized, "It should reject an invalid recovery code")
                }
            )

            let goodTempToken = try await app.loginForTempToken(username: "otavio", password: "correct-horse-battery")
            try await app.testing().test(
                .POST, "api/v1/auth/recovery",
                beforeRequest: { req in
                    try req.content.encode(RecoveryRequest(tempToken: goodTempToken, recoveryCode: codes[0]))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .ok, "It should accept a valid recovery code")
                }
            )

            // Then
            let rows = try await AuditLog.query(on: app.db).all()
            #expect(
                rows.contains { $0.action == "login_failure" },
                "It should record a login_failure row for the bad recovery code"
            )
            #expect(
                rows.contains { $0.action == "login_success" },
                "It should record a login_success row for the valid recovery code"
            )
        }
    }

    private func enrol(_ app: Application, accessToken: String) async throws -> (secret: String, codes: [String]) {
        var secret: String?
        try await app.testing().test(
            .GET, "api/v1/auth/totp/setup",
            headers: ["Authorization": "Bearer \(accessToken)"]
        ) { res async throws in
            #expect(res.status == .ok, "It should return 200 OK")
            let setup = try res.content.decode(TOTPSetupResponse.self)
            #expect(!setup.secret.isEmpty, "It should return a non-empty secret")
            #expect(setup.otpauthURI.hasPrefix("otpauth://totp/"), "It should return a valid otpauth URI")
            secret = setup.secret
        }

        let code = TOTP(secret: Base32.decode(secret!)!).generate()
        var codes: [String] = []
        try await app.testing().test(
            .POST, "api/v1/auth/totp/verify-setup",
            headers: ["Authorization": "Bearer \(accessToken)"],
            beforeRequest: { req in
                try req.content.encode(VerifySetupRequest(totpCode: code))
            },
            afterResponse: { res async throws in
                #expect(res.status == .ok, "It should return 200 OK")
                codes = try res.content.decode(RecoveryCodesResponse.self).recoveryCodes
                #expect(codes.count == 8, "It should return eight recovery codes")
            }
        )
        return (secret!, codes)
    }
}
