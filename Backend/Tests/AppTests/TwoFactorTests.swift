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

@Suite("Auth — TOTP 2FA enrolment and login")
struct TwoFactorTests {

    @Test("enrolment returns 8 recovery codes and enables 2FA")
    func enrolment() async throws {
        try await withTestApp { app in
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let (_, codes) = try await enrol(app, accessToken: pair.accessToken)
            #expect(codes.count == 8)
            #expect(codes.allSatisfy { $0.contains("-") })

            // After enrolment, login should now require 2FA.
            try await app.testing().test(
                .POST, "api/v1/auth/login",
                beforeRequest: { req in
                    try req.content.encode(LoginRequest(username: "otavio", password: "correct-horse-battery"))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    let challenge = try res.content.decode(TwoFactorRequired.self)
                    #expect(challenge.requires2FA == true)
                    #expect(!challenge.tempToken.isEmpty)
                }
            )
        }
    }

    @Test("verify-setup with a wrong code is rejected")
    func verifySetupWrongCode() async throws {
        try await withTestApp { app in
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            // begin setup
            try await app.testing().test(
                .GET, "api/v1/auth/totp/setup",
                headers: ["Authorization": "Bearer \(pair.accessToken)"]
            ) { res async throws in #expect(res.status == .ok) }
            try await app.testing().test(
                .POST, "api/v1/auth/totp/verify-setup",
                headers: ["Authorization": "Bearer \(pair.accessToken)"],
                beforeRequest: { req in
                    try req.content.encode(VerifySetupRequest(totpCode: "000000"))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unauthorized)
                    let err = try res.content.decode(TestError.self)
                    #expect(err.code == "totp_invalid")
                }
            )
        }
    }

    @Test("full 2FA login flow: tempToken + valid TOTP code yields a token pair")
    func totpLogin() async throws {
        try await withTestApp { app in
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let (secret, _) = try await enrol(app, accessToken: pair.accessToken)

            let tempToken = try await app.loginForTempToken(username: "otavio", password: "correct-horse-battery")
            let code = TOTP(secret: Base32.decode(secret)!).generate()

            try await app.testing().test(
                .POST, "api/v1/auth/totp",
                beforeRequest: { req in
                    try req.content.encode(TOTPRequest(tempToken: tempToken, totpCode: code))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    let tokens = try res.content.decode(TokenPair.self)
                    #expect(!tokens.accessToken.isEmpty)
                    #expect(!tokens.refreshToken.isEmpty)
                }
            )
        }
    }

    @Test("wrong TOTP code after login is rejected")
    func totpLoginWrongCode() async throws {
        try await withTestApp { app in
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            _ = try await enrol(app, accessToken: pair.accessToken)

            let tempToken = try await app.loginForTempToken(username: "otavio", password: "correct-horse-battery")
            try await app.testing().test(
                .POST, "api/v1/auth/totp",
                beforeRequest: { req in
                    try req.content.encode(TOTPRequest(tempToken: tempToken, totpCode: "000000"))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unauthorized)
                    let err = try res.content.decode(TestError.self)
                    #expect(err.code == "totp_invalid")
                }
            )
        }
    }

    @Test("recovery code redeems once and cannot be reused")
    func recoveryCodeSingleUse() async throws {
        try await withTestApp { app in
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let (_, codes) = try await enrol(app, accessToken: pair.accessToken)
            let recoveryCode = codes[0]

            // First use succeeds.
            let tempToken1 = try await app.loginForTempToken(username: "otavio", password: "correct-horse-battery")
            try await app.testing().test(
                .POST, "api/v1/auth/recovery",
                beforeRequest: { req in
                    try req.content.encode(RecoveryRequest(tempToken: tempToken1, recoveryCode: recoveryCode))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    _ = try res.content.decode(TokenPair.self)
                }
            )

            // Second use of the same code fails.
            let tempToken2 = try await app.loginForTempToken(username: "otavio", password: "correct-horse-battery")
            try await app.testing().test(
                .POST, "api/v1/auth/recovery",
                beforeRequest: { req in
                    try req.content.encode(RecoveryRequest(tempToken: tempToken2, recoveryCode: recoveryCode))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unauthorized)
                    let err = try res.content.decode(TestError.self)
                    #expect(err.code == "totp_invalid")
                }
            )
        }
    }

    @Test("totp endpoint rejects a malformed temp token")
    func totpBadTempToken() async throws {
        try await withTestApp { app in
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            try await app.testing().test(
                .POST, "api/v1/auth/totp",
                beforeRequest: { req in
                    try req.content.encode(TOTPRequest(tempToken: "not-a-jwt", totpCode: "123456"))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unauthorized)
                    let err = try res.content.decode(TestError.self)
                    #expect(err.code == "token_invalid")
                }
            )
        }
    }

    /// Enrol the user in 2FA via the API; returns (secret, recoveryCodes).
    private func enrol(_ app: Application, accessToken: String) async throws -> (secret: String, codes: [String]) {
        var secret: String?
        try await app.testing().test(
            .GET, "api/v1/auth/totp/setup",
            headers: ["Authorization": "Bearer \(accessToken)"]
        ) { res async throws in
            #expect(res.status == .ok)
            let setup = try res.content.decode(TOTPSetupResponse.self)
            #expect(!setup.secret.isEmpty)
            #expect(setup.otpauthURI.hasPrefix("otpauth://totp/"))
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
                #expect(res.status == .ok)
                codes = try res.content.decode(RecoveryCodesResponse.self).recoveryCodes
                #expect(codes.count == 8)
            }
        )
        return (secret!, codes)
    }
}
