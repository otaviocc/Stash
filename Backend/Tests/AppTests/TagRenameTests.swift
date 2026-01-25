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

import Fluent
import Testing
import VaporTesting
@testable import App

/// Covers renaming a tag (and its descendants), including merge and no-op cases.
@Suite("Tags — rename")
struct TagRenameTests {

    @Test("renames the exact tag and its children, leaving others alone")
    func renameWithChildren() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let exact = try await app.makeBookmark(for: user, url: "https://1.com", tags: ["foo-bar"])
            let child = try await app.makeBookmark(for: user, url: "https://2.com", tags: ["foo-bar/swift", "other"])
            let unrelated = try await app.makeBookmark(for: user, url: "https://3.com", tags: ["unrelated"])

            // When
            let result = try await rename(app, token: pair.accessToken, from: "foo-bar", to: "foobar")

            // Then
            #expect(result?.from == "foo-bar", "It should echo the source tag")
            #expect(result?.to == "foobar", "It should echo the target tag")
            #expect(result?.affectedBookmarks == 2, "It should report two affected bookmarks")

            let exactTags = try await Bookmark.find(exact.requireID(), on: app.db)?.tags
            let childTags = try await Bookmark.find(child.requireID(), on: app.db)?.tags
            let unrelatedTags = try await Bookmark.find(unrelated.requireID(), on: app.db)?.tags
            #expect(exactTags == ["foobar"], "It should rename the exact tag")
            #expect(childTags == ["foobar/swift", "other"], "It should rename the child tag and keep others")
            #expect(unrelatedTags == ["unrelated"], "It should not touch the unrelated bookmark")
        }
    }

    @Test("renaming onto an existing tag merges without duplicates")
    func renameMerges() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let exact = try await app.makeBookmark(for: user, url: "https://a.com", tags: ["foo-bar", "foobar", "keep"])
            let child = try await app.makeBookmark(for: user, url: "https://b.com", tags: ["foo-bar/x", "foobar/x"])

            // When
            let result = try await rename(app, token: pair.accessToken, from: "foo-bar", to: "foobar")

            // Then
            #expect(result?.affectedBookmarks == 2, "It should report two affected bookmarks")

            let exactTags = try await Bookmark.find(exact.requireID(), on: app.db)?.tags
            let childTags = try await Bookmark.find(child.requireID(), on: app.db)?.tags
            #expect(exactTags == ["foobar", "keep"], "It should de-duplicate while preserving order")
            #expect(childTags == ["foobar/x"], "It should merge duplicate child tags")
        }
    }

    @Test("renaming a tag that doesn't exist is a 200 no-op")
    func renameMissing() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let b = try await app.makeBookmark(for: user, url: "https://a.com", tags: ["alpha"])

            // When
            let result = try await rename(app, token: pair.accessToken, from: "ghost", to: "beta")

            // Then
            #expect(result?.affectedBookmarks == 0, "It should report zero affected bookmarks")

            let tags = try await Bookmark.find(b.requireID(), on: app.db)?.tags
            #expect(tags == ["alpha"], "It should leave the existing tag untouched")
        }
    }

    @Test("from equals to (after normalization) is a 200 no-op")
    func renameNoop() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let b = try await app.makeBookmark(for: user, url: "https://a.com", tags: ["same"])

            // When
            let result = try await rename(app, token: pair.accessToken, from: "same", to: "SAME")

            // Then
            #expect(result?.from == "same", "It should echo the normalized source tag")
            #expect(result?.to == "same", "It should echo the normalized target tag")
            #expect(result?.affectedBookmarks == 0, "It should report zero affected bookmarks")

            let tags = try await Bookmark.find(b.requireID(), on: app.db)?.tags
            #expect(tags == ["same"], "It should leave the tag untouched")
        }
    }

    @Test("empty from or to is rejected with 422")
    func renameEmptyValidation() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            // When
            for (from, to) in [("", "x"), ("x", ""), ("///", "x"), ("x", "  ")] {
                try await app.testing().test(
                    .POST, "api/v1/tags/rename",
                    headers: bearer(pair.accessToken),
                    beforeRequest: { req in try req.content.encode(TagRenameRequest(from: from, to: to)) },
                    afterResponse: { res async throws in
                        // Then
                        #expect(res.status == .unprocessableEntity, "It should return 422 Unprocessable Entity")
                        #expect(
                            try res.content.decode(TestError.self).code == "validation_failed",
                            "It should return the validation_failed code"
                        )
                    }
                )
            }
        }
    }

    @Test("a user cannot rename another user's tags")
    func renameUserIsolation() async throws {
        try await withTestApp { app in
            // Given
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123")
            try await app.makeUser(username: "bob", password: "bob-password-12345")
            let aliceBookmark = try await app.makeBookmark(for: alice, url: "https://alice.com", tags: ["foo-bar"])

            // When
            let bob = try await app.login(username: "bob", password: "bob-password-12345")
            let result = try await rename(app, token: bob.accessToken, from: "foo-bar", to: "foobar")

            // Then
            #expect(result?.affectedBookmarks == 0, "It should report zero affected bookmarks")

            let aliceTags = try await Bookmark.find(aliceBookmark.requireID(), on: app.db)?.tags
            #expect(aliceTags == ["foo-bar"], "It should leave the other user's tag untouched")
        }
    }

    private func rename(
        _ app: Application,
        token: String,
        from: String,
        to: String,
        expect status: HTTPResponseStatus = .ok
    ) async throws -> TagRenameResponse? {
        var decoded: TagRenameResponse?
        try await app.testing().test(
            .POST, "api/v1/tags/rename",
            headers: bearer(token),
            beforeRequest: { req in try req.content.encode(TagRenameRequest(from: from, to: to)) },
            afterResponse: { res async throws in
                #expect(res.status == status, "It should return the expected status")
                if status == .ok { decoded = try res.content.decode(TagRenameResponse.self) }
            }
        )
        return decoded
    }
}
