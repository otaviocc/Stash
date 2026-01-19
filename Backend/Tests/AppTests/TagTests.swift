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
                headers: bearer(pair.accessToken)
            ) { res async throws in
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
        }
    }

    @Test("GET /tags requires authentication")
    func tagsRequireAuth() async throws {
        try await withTestApp { app in
            try await app.testing().test(.GET, "api/v1/tags") { res async throws in
                #expect(res.status == .unauthorized)
            }
        }
    }
}
