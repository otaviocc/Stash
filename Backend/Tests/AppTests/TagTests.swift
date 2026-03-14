import Testing
import VaporTesting

@testable import App

@Suite("Tags — aggregation")
struct TagTests {
    @Test("GET /tags returns each distinct tag with its count, sorted, scoped to the user")
    func tagCounts() async throws {
        try await withTestApp { app in
            let user = try await app.makeUser()
            let other = try await app.makeUser(username: "bob", password: "bob-password-12345")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            try await app.makeBookmark(for: user, url: "https://1.com", tags: ["swift", "swift/vapor"])
            try await app.makeBookmark(for: user, url: "https://2.com", tags: ["swift", "music/jazz"])
            try await app.makeBookmark(for: user, url: "https://3.com", tags: ["swift/vapor"])
            // Another user's tags must not leak in.
            try await app.makeBookmark(for: other, url: "https://x.com", tags: ["other-tag"])

            try await app.testing().test(
                .GET, "api/v1/tags",
                headers: bearer(pair.accessToken),
                afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    let tags = try res.content.decode([TagCount].self)
                    let byName = Dictionary(uniqueKeysWithValues: tags.map { ($0.name, $0.count) })
                    #expect(byName["swift"] == 2)
                    #expect(byName["swift/vapor"] == 2)
                    #expect(byName["music/jazz"] == 1)
                    #expect(byName["other-tag"] == nil)
                    // Sorted alphabetically.
                    #expect(tags.map(\.name) == tags.map(\.name).sorted())
                }
            )
        }
    }

    @Test("GET /tags requires authentication")
    func tagsRequireAuth() async throws {
        try await withTestApp { app in
            try await app.testing().test(.GET, "api/v1/tags", afterResponse: { res async throws in
                #expect(res.status == .unauthorized)
            })
        }
    }
}
