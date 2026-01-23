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

@Suite("Tags — delete")
struct TagDeleteTests {

    @Test("deletes the exact tag from every bookmark that had it")
    func deleteExact() async throws {
        try await withTestApp { app in
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let one = try await app.makeBookmark(for: user, url: "https://1.com", tags: ["foo-bar", "keep"])
            let two = try await app.makeBookmark(for: user, url: "https://2.com", tags: ["foo-bar"])
            let unrelated = try await app.makeBookmark(for: user, url: "https://3.com", tags: ["unrelated"])

            let result = try await delete(app, token: pair.accessToken, tag: "foo-bar")
            #expect(result?.tag == "foo-bar")
            #expect(result?.affectedBookmarks == 2)

            let oneTags = try await Bookmark.find(one.requireID(), on: app.db)?.tags
            let twoTags = try await Bookmark.find(two.requireID(), on: app.db)?.tags
            let unrelatedTags = try await Bookmark.find(unrelated.requireID(), on: app.db)?.tags
            #expect(oneTags == ["keep"])
            #expect(twoTags == [])
            #expect(unrelatedTags == ["unrelated"])
        }
    }

    @Test("deletes the tag's children too")
    func deleteWithChildren() async throws {
        try await withTestApp { app in
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let exact = try await app.makeBookmark(for: user, url: "https://1.com", tags: ["foo-bar"])
            let child = try await app.makeBookmark(for: user, url: "https://2.com", tags: ["foo-bar/swift", "other"])
            let grandchild = try await app.makeBookmark(for: user, url: "https://3.com", tags: ["foo-bar/swift/vapor"])
            // A look-alike that is NOT a child (no slash boundary) must be untouched.
            let lookalike = try await app.makeBookmark(for: user, url: "https://4.com", tags: ["foo-barbaz"])

            let result = try await delete(app, token: pair.accessToken, tag: "foo-bar")
            #expect(result?.affectedBookmarks == 3)

            let exactTags = try await Bookmark.find(exact.requireID(), on: app.db)?.tags
            let childTags = try await Bookmark.find(child.requireID(), on: app.db)?.tags
            let grandchildTags = try await Bookmark.find(grandchild.requireID(), on: app.db)?.tags
            let lookalikeTags = try await Bookmark.find(lookalike.requireID(), on: app.db)?.tags
            #expect(exactTags == [])
            #expect(childTags == ["other"])
            #expect(grandchildTags == [])
            #expect(lookalikeTags == ["foo-barbaz"])
        }
    }

    @Test("deleting a tag that doesn't exist is a 200 no-op")
    func deleteMissing() async throws {
        try await withTestApp { app in
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let bookmark = try await app.makeBookmark(for: user, url: "https://a.com", tags: ["alpha"])

            let result = try await delete(app, token: pair.accessToken, tag: "ghost")
            #expect(result?.affectedBookmarks == 0)

            let tags = try await Bookmark.find(bookmark.requireID(), on: app.db)?.tags
            #expect(tags == ["alpha"])
        }
    }

    @Test("an empty tag is rejected with 422")
    func deleteEmptyValidation() async throws {
        try await withTestApp { app in
            try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            // "%2F%2F%2F" (= "///") and "%20%20" (= whitespace) normalise to empty after
            // stripping surrounding slashes / trimming — both decode to a single path segment.
            for tag in ["%2F%2F%2F", "%20%20"] {
                try await app.testing().test(
                    .DELETE, "api/v1/tags/\(tag)",
                    headers: bearer(pair.accessToken)
                ) { res async throws in
                    #expect(res.status == .unprocessableEntity)
                    #expect(try res.content.decode(TestError.self).code == "validation_failed")
                }
            }
        }
    }

    @Test("a user cannot delete another user's tags")
    func deleteUserIsolation() async throws {
        try await withTestApp { app in
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123")
            try await app.makeUser(username: "bob", password: "bob-password-12345")
            let aliceBookmark = try await app.makeBookmark(for: alice, url: "https://alice.com", tags: ["foo-bar"])

            let bob = try await app.login(username: "bob", password: "bob-password-12345")
            let result = try await delete(app, token: bob.accessToken, tag: "foo-bar")
            #expect(result?.affectedBookmarks == 0)

            let aliceTags = try await Bookmark.find(aliceBookmark.requireID(), on: app.db)?.tags
            #expect(aliceTags == ["foo-bar"])
        }
    }

    @Test("a bookmark whose only tag is deleted survives with an empty tag array")
    func deleteLeavesBookmarkWithNoTags() async throws {
        try await withTestApp { app in
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let bookmark = try await app.makeBookmark(for: user, url: "https://only.com", tags: ["solo"])

            let result = try await delete(app, token: pair.accessToken, tag: "solo")
            #expect(result?.affectedBookmarks == 1)

            let stored = try await Bookmark.find(bookmark.requireID(), on: app.db)
            #expect(stored != nil)
            #expect(stored?.tags == [])
        }
    }

    private func delete(
        _ app: Application,
        token: String,
        tag: String,
        expect status: HTTPResponseStatus = .ok
    ) async throws -> TagDeleteResponse? {
        var decoded: TagDeleteResponse?
        let encoded = tag
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(.init(charactersIn: "/"))) ?? tag
        try await app.testing().test(
            .DELETE, "api/v1/tags/\(encoded)",
            headers: bearer(token)
        ) { res async throws in
            #expect(res.status == status)
            if status == .ok { decoded = try res.content.decode(TagDeleteResponse.self) }
        }
        return decoded
    }
}
