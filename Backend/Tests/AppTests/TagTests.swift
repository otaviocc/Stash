// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Testing
import VaporTesting
@testable import App

/// Covers the tag aggregation endpoint and its per-user scoping.
@Suite("Tags: aggregation")
struct TagTests {

    @Test("GET /tags returns each distinct tag with its count, sorted, scoped to the user")
    func tagCounts() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let other = try await app.makeUser(username: "bob", password: "bob-password-12345")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            try await app.makeBookmark(for: user, url: "https://1.com", tags: ["swift", "swift/vapor"])
            try await app.makeBookmark(for: user, url: "https://2.com", tags: ["swift", "music/jazz"])
            try await app.makeBookmark(for: user, url: "https://3.com", tags: ["swift/vapor"])
            try await app.makeBookmark(for: other, url: "https://x.com", tags: ["other-tag"])

            // When
            try await app.testing().test(
                .GET, "api/v1/tags",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                #expect(res.status == .ok, "It should return 200 OK")
                let tags = try res.content.decode([TagCount].self)
                let byName = Dictionary(uniqueKeysWithValues: tags.map { ($0.name, $0.count) })
                #expect(byName["swift"] == 2, "It should count the swift tag twice")
                #expect(byName["swift/vapor"] == 2, "It should count the swift/vapor tag twice")
                #expect(byName["music/jazz"] == 1, "It should count the music/jazz tag once")
                #expect(byName["other-tag"] == nil, "It should not leak another user's tags")
                #expect(tags.map(\.name) == tags.map(\.name).sorted(), "It should return tags sorted alphabetically")
            }
        }
    }

    @Test("GET /tags requires authentication")
    func tagsRequireAuth() async throws {
        try await withTestApp { app in
            // Given: no setup required

            // When
            try await app.testing().test(.GET, "api/v1/tags") { res async throws in
                // Then
                #expect(res.status == .unauthorized, "It should return 401 Unauthorized")
            }
        }
    }
}
