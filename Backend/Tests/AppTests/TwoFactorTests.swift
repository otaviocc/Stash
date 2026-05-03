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

import Testing
import VaporTesting
@testable import App

/// Covers TOTP-based two-factor enrollment, login, and recovery-code flows.
@Suite("Auth — TOTP 2FA enrollment and login")
struct TwoFactorTests {

    @Test("enrollment returns 8 recovery codes and enables 2FA")
    func enrolment() async throws {
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
