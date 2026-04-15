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

@Suite("Account — /me and password change")
struct AccountTests {

    @Test("GET /me returns the current user profile")
    func me() async throws {
        try await withTestApp { app in
            try await app.makeUser(username: "otavio", password: "correct-horse-battery", role: .admin)
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            try await app.testing().test(
                .GET, "api/v1/me",
                headers: ["Authorization": "Bearer \(pair.accessToken)"]
            ) { res async throws in
                #expect(res.status == .ok)
                let user = try res.content.decode(UserResponse.self)
                #expect(user.username == "otavio")
                #expect(user.role == .admin)
                #expect(user.isTOTPEnabled == false)
            }
        }
    }

    @Test("password change requires the correct current password")
    func changePasswordWrongCurrent() async throws {
        try await withTestApp { app in
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            try await app.testing().test(
                .PUT, "api/v1/me/password",
                headers: ["Authorization": "Bearer \(pair.accessToken)"],
                beforeRequest: { req in
                    try req.content.encode(ChangePasswordRequest(
                        currentPassword: "wrong-current-pw",
                        newPassword: "a-brand-new-password"
                    ))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unauthorized)
                    let err = try res.content.decode(TestError.self)
                    #expect(err.code == "invalid_credentials")
                }
            )
        }
    }

    @Test("new password under 12 characters fails validation")
    func changePasswordTooShort() async throws {
        try await withTestApp { app in
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            try await app.testing().test(
                .PUT, "api/v1/me/password",
                headers: ["Authorization": "Bearer \(pair.accessToken)"],
                beforeRequest: { req in
                    try req.content.encode(ChangePasswordRequest(
                        currentPassword: "correct-horse-battery",
                        newPassword: "short"
                    ))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unprocessableEntity)
                    let err = try res.content.decode(TestError.self)
                    #expect(err.code == "validation_failed")
                }
            )
        }
    }

    @Test("password change succeeds, then the new password works for login")
    func changePasswordSuccess() async throws {
        try await withTestApp { app in
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            try await app.testing().test(
                .PUT, "api/v1/me/password",
                headers: ["Authorization": "Bearer \(pair.accessToken)"],
                beforeRequest: { req in
                    try req.content.encode(ChangePasswordRequest(
                        currentPassword: "correct-horse-battery",
                        newPassword: "a-brand-new-password"
                    ))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .noContent)
                }
            )

            _ = try await app.login(username: "otavio", password: "a-brand-new-password")
        }
    }
}
