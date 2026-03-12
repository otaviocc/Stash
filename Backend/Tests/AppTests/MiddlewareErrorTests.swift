import Testing
import VaporTesting

@testable import App

@Suite("Middleware & error envelope")
struct MiddlewareErrorTests {
    @Test("health check is reachable and unversioned")
    func health() async throws {
        try await withTestApp { app in
            try await app.testing().test(.GET, "health", afterResponse: { res async throws in
                #expect(res.status == .ok)
                let body = try res.content.decode(HealthResponse.self)
                #expect(body.status == "ok")
            })
        }
    }

    @Test("unauthenticated request to a protected route is rejected with 401")
    func unauthenticatedRejected() async throws {
        try await withTestApp { app in
            try await app.testing().test(.GET, "api/v1/me", afterResponse: { res async throws in
                #expect(res.status == .unauthorized)
                let err = try res.content.decode(TestError.self)
                #expect(err.error == true)
                #expect(err.code == "token_invalid")
            })
        }
    }

    @Test("a garbage bearer token is rejected with token_invalid")
    func garbageToken() async throws {
        try await withTestApp { app in
            try await app.testing().test(
                .GET, "api/v1/me",
                headers: ["Authorization": "Bearer total-garbage"],
                afterResponse: { res async throws in
                    #expect(res.status == .unauthorized)
                    let err = try res.content.decode(TestError.self)
                    #expect(err.code == "token_invalid")
                }
            )
        }
    }

    @Test("unmatched route returns a 404 in the standard envelope")
    func notFoundEnvelope() async throws {
        try await withTestApp { app in
            try await app.testing().test(.GET, "api/v1/does-not-exist", afterResponse: { res async throws in
                #expect(res.status == .notFound)
                let err = try res.content.decode(TestError.self)
                #expect(err.error == true)
                #expect(err.code == "not_found")
                #expect(!err.message.isEmpty)
            })
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
