import Fluent
import Testing
import Vapor
import VaporTesting
@testable import App
@Suite("audit render (throwaway)")
struct AuditRenderTests {
    @Test("/app sidebar still renders after field removal")
    func render() async throws {
        try await withTestApp { app in
            let user = try await app.makeUser(username: "alice", password: "alice-password-123")
            try await app.makeBookmark(for: user, url: "https://a.com", tags: ["swift/vapor"])
            var s = HTTPHeaders()
            try await app.testing().test(.POST, "app/login",
                beforeRequest: { req in try req.content.encode(["username": "alice", "password": "alice-password-123"], as: .urlEncodedForm) },
                afterResponse: { res async throws in if let v = res.headers.setCookie?["stash_session"]?.string { s.replaceOrAdd(name: .cookie, value: "stash_session=\(v)") } })
            try await app.testing().test(.GET, "app", headers: s, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let b = res.body.string
                #expect(b.contains("tag-sidebar"))
                #expect(b.contains(#"href="/app?tag=swift%2Fvapor""#))  // href still works
                #expect(b.contains(">vapor<"))                          // label still works
                #expect(!b.contains("position: fixed"))
                #expect(!b.contains("position: sticky"))
            })
        }
    }
}
