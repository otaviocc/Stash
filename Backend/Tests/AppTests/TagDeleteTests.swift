// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Testing
import VaporTesting
@testable import App

/// Covers deleting a tag (and its descendants) across a user's bookmarks.
@Suite("Tags — delete")
struct TagDeleteTests {

    @Test("deletes the exact tag from every bookmark that had it")
    func deleteExact() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let one = try await app.makeBookmark(for: user, url: "https://1.com", tags: ["foo-bar", "keep"])
            let two = try await app.makeBookmark(for: user, url: "https://2.com", tags: ["foo-bar"])
            let unrelated = try await app.makeBookmark(for: user, url: "https://3.com", tags: ["unrelated"])

            // When
            let result = try await delete(app, token: pair.accessToken, tag: "foo-bar")

            // Then
            #expect(result?.tag == "foo-bar", "It should echo the deleted tag")
            #expect(result?.affectedBookmarks == 2, "It should report two affected bookmarks")

            let oneTags = try await Bookmark.find(one.requireID(), on: app.db)?.tags
            let twoTags = try await Bookmark.find(two.requireID(), on: app.db)?.tags
            let unrelatedTags = try await Bookmark.find(unrelated.requireID(), on: app.db)?.tags
            #expect(oneTags == ["keep"], "It should keep the remaining tag on the first bookmark")
            #expect(twoTags == [], "It should leave the second bookmark with no tags")
            #expect(unrelatedTags == ["unrelated"], "It should not touch the unrelated bookmark")
        }
    }

    @Test("deletes the tag's children too")
    func deleteWithChildren() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let exact = try await app.makeBookmark(for: user, url: "https://1.com", tags: ["foo-bar"])
            let child = try await app.makeBookmark(for: user, url: "https://2.com", tags: ["foo-bar/swift", "other"])
            let grandchild = try await app.makeBookmark(for: user, url: "https://3.com", tags: ["foo-bar/swift/vapor"])
            let lookalike = try await app.makeBookmark(for: user, url: "https://4.com", tags: ["foo-barbaz"])

            // When
            let result = try await delete(app, token: pair.accessToken, tag: "foo-bar")

            // Then
            #expect(result?.affectedBookmarks == 3, "It should report three affected bookmarks")

            let exactTags = try await Bookmark.find(exact.requireID(), on: app.db)?.tags
            let childTags = try await Bookmark.find(child.requireID(), on: app.db)?.tags
            let grandchildTags = try await Bookmark.find(grandchild.requireID(), on: app.db)?.tags
            let lookalikeTags = try await Bookmark.find(lookalike.requireID(), on: app.db)?.tags
            #expect(exactTags == [], "It should remove the exact tag")
            #expect(childTags == ["other"], "It should remove the child tag but keep others")
            #expect(grandchildTags == [], "It should remove the grandchild tag")
            #expect(lookalikeTags == ["foo-barbaz"], "It should not touch a look-alike tag")
        }
    }

    @Test("deleting a tag that doesn't exist is a 200 no-op")
    func deleteMissing() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let bookmark = try await app.makeBookmark(for: user, url: "https://a.com", tags: ["alpha"])

            // When
            let result = try await delete(app, token: pair.accessToken, tag: "ghost")

            // Then
            #expect(result?.affectedBookmarks == 0, "It should report zero affected bookmarks")

            let tags = try await Bookmark.find(bookmark.requireID(), on: app.db)?.tags
            #expect(tags == ["alpha"], "It should leave the existing tag untouched")
        }
    }

    @Test("an empty tag is rejected with 422", arguments: ["%2F%2F%2F", "%20%20"])
    func deleteEmptyValidation(tag: String) async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            // When
            try await app.testing().test(
                .DELETE, "api/v1/tags/\(tag)",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                #expect(
                    res.status == .unprocessableEntity,
                    "It should reject '\(tag)' with 422 Unprocessable Entity"
                )
                #expect(
                    try res.content.decode(TestError.self).code == "validation_failed",
                    "It should return the validation_failed code"
                )
            }
        }
    }

    @Test("a user cannot delete another user's tags")
    func deleteUserIsolation() async throws {
        try await withTestApp { app in
            // Given
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123")
            try await app.makeUser(username: "bob", password: "bob-password-12345")
            let aliceBookmark = try await app.makeBookmark(for: alice, url: "https://alice.com", tags: ["foo-bar"])

            // When
            let bob = try await app.login(username: "bob", password: "bob-password-12345")
            let result = try await delete(app, token: bob.accessToken, tag: "foo-bar")

            // Then
            #expect(result?.affectedBookmarks == 0, "It should report zero affected bookmarks")

            let aliceTags = try await Bookmark.find(aliceBookmark.requireID(), on: app.db)?.tags
            #expect(aliceTags == ["foo-bar"], "It should leave the other user's tag untouched")
        }
    }

    @Test("a bookmark whose only tag is deleted survives with an empty tag array")
    func deleteLeavesBookmarkWithNoTags() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let bookmark = try await app.makeBookmark(for: user, url: "https://only.com", tags: ["solo"])

            // When
            let result = try await delete(app, token: pair.accessToken, tag: "solo")

            // Then
            #expect(result?.affectedBookmarks == 1, "It should report one affected bookmark")

            let stored = try await Bookmark.find(bookmark.requireID(), on: app.db)
            #expect(stored != nil, "It should keep the bookmark")
            #expect(stored?.tags == [], "It should leave the bookmark with an empty tag array")
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
            #expect(res.status == status, "It should return the expected status")
            if status == .ok {
                decoded = try res.content.decode(TagDeleteResponse.self)
            }
        }
        return decoded
    }
}
