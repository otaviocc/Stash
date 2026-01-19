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

@Suite("Middleware & error envelope")
struct MiddlewareErrorTests {

    @Test("health check is reachable and unversioned")
    func health() async throws {
        try await withTestApp { app in
            try await app.testing().test(.GET, "health") { res async throws in
                #expect(res.status == .ok)
                let body = try res.content.decode(HealthResponse.self)
                #expect(body.status == "ok")
            }
        }
    }

    @Test("unauthenticated request to a protected route is rejected with 401")
    func unauthenticatedRejected() async throws {
        try await withTestApp { app in
            try await app.testing().test(.GET, "api/v1/me") { res async throws in
                #expect(res.status == .unauthorized)
                let err = try res.content.decode(TestError.self)
                #expect(err.error == true)
                #expect(err.code == "token_invalid")
            }
        }
    }

    @Test("a garbage bearer token is rejected with token_invalid")
    func garbageToken() async throws {
        try await withTestApp { app in
            try await app.testing().test(
                .GET, "api/v1/me",
                headers: ["Authorization": "Bearer total-garbage"]
            ) { res async throws in
                #expect(res.status == .unauthorized)
                let err = try res.content.decode(TestError.self)
                #expect(err.code == "token_invalid")
            }
        }
    }

    @Test("unmatched route returns a 404 in the standard envelope")
    func notFoundEnvelope() async throws {
        try await withTestApp { app in
            try await app.testing().test(.GET, "api/v1/does-not-exist") { res async throws in
                #expect(res.status == .notFound)
                let err = try res.content.decode(TestError.self)
                #expect(err.error == true)
                #expect(err.code == "not_found")
                #expect(!err.message.isEmpty)
            }
        }
    }

    @Test("all error responses carry error:true, a code, and a message")
    func errorEnvelopeShape() async throws {
        try await withTestApp { app in
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            try await app.testing().test(
                .POST, "api/v1/auth/login",
                beforeRequest: { req in
                    try req.content.encode(LoginRequest(username: "otavio", password: "definitely-wrong"))
                },
                afterResponse: { res async throws in
                    #expect(res.headers.contentType?.subType == "json")
                    let err = try res.content.decode(TestError.self)
                    #expect(err.error == true)
                    #expect(!err.code.isEmpty)
                    #expect(!err.message.isEmpty)
                }
            )
        }
    }
}
