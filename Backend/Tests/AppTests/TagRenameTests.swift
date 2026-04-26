import Fluent
import Testing
import VaporTesting

@testable import App

@Suite("Tags — rename")
struct TagRenameTests {
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
                #expect(res.status == status)
                if status == .ok { decoded = try res.content.decode(TagRenameResponse.self) }
            }
        )
        return decoded
    }

    @Test("renames the exact tag and its children, leaving others alone")
    func renameWithChildren() async throws {
        try await withTestApp { app in
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let exact = try await app.makeBookmark(for: user, url: "https://1.com", tags: ["foo-bar"])
            let child = try await app.makeBookmark(for: user, url: "https://2.com", tags: ["foo-bar/swift", "other"])
            let unrelated = try await app.makeBookmark(for: user, url: "https://3.com", tags: ["unrelated"])

            let result = try await rename(app, token: pair.accessToken, from: "foo-bar", to: "foobar")
            #expect(result?.from == "foo-bar")
            #expect(result?.to == "foobar")
            #expect(result?.affectedBookmarks == 2)

            let exactTags = try await Bookmark.find(exact.requireID(), on: app.db)?.tags
            let childTags = try await Bookmark.find(child.requireID(), on: app.db)?.tags
            let unrelatedTags = try await Bookmark.find(unrelated.requireID(), on: app.db)?.tags
            #expect(exactTags == ["foobar"])
            #expect(childTags == ["foobar/swift", "other"])
            #expect(unrelatedTags == ["unrelated"])
        }
    }

    @Test("renaming onto an existing tag merges without duplicates")
    func renameMerges() async throws {
        try await withTestApp { app in
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let exact = try await app.makeBookmark(for: user, url: "https://a.com", tags: ["foo-bar", "foobar", "keep"])
            let child = try await app.makeBookmark(for: user, url: "https://b.com", tags: ["foo-bar/x", "foobar/x"])

            let result = try await rename(app, token: pair.accessToken, from: "foo-bar", to: "foobar")
            #expect(result?.affectedBookmarks == 2)

            let exactTags = try await Bookmark.find(exact.requireID(), on: app.db)?.tags
            let childTags = try await Bookmark.find(child.requireID(), on: app.db)?.tags
            // De-duplicated, order preserved.
            #expect(exactTags == ["foobar", "keep"])
            #expect(childTags == ["foobar/x"])
        }
    }

    @Test("renaming a tag that doesn't exist is a 200 no-op")
    func renameMissing() async throws {
        try await withTestApp { app in
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let b = try await app.makeBookmark(for: user, url: "https://a.com", tags: ["alpha"])

            let result = try await rename(app, token: pair.accessToken, from: "ghost", to: "beta")
            #expect(result?.affectedBookmarks == 0)

            let tags = try await Bookmark.find(b.requireID(), on: app.db)?.tags
            #expect(tags == ["alpha"])
        }
    }

    @Test("from equals to (after normalisation) is a 200 no-op")
    func renameNoop() async throws {
        try await withTestApp { app in
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let b = try await app.makeBookmark(for: user, url: "https://a.com", tags: ["same"])

            // "SAME" normalises to "same", which equals `from`.
            let result = try await rename(app, token: pair.accessToken, from: "same", to: "SAME")
            #expect(result?.from == "same")
            #expect(result?.to == "same")
            #expect(result?.affectedBookmarks == 0)

            let tags = try await Bookmark.find(b.requireID(), on: app.db)?.tags
            #expect(tags == ["same"])
        }
    }

    @Test("empty from or to is rejected with 422")
    func renameEmptyValidation() async throws {
        try await withTestApp { app in
            try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            for (from, to) in [("", "x"), ("x", ""), ("///", "x"), ("x", "  ")] {
                try await app.testing().test(
                    .POST, "api/v1/tags/rename",
                    headers: bearer(pair.accessToken),
                    beforeRequest: { req in try req.content.encode(TagRenameRequest(from: from, to: to)) },
                    afterResponse: { res async throws in
                        #expect(res.status == .unprocessableEntity)
                        #expect(try res.content.decode(TestError.self).code == "validation_failed")
                    }
                )
            }
        }
    }

    @Test("a user cannot rename another user's tags")
    func renameUserIsolation() async throws {
        try await withTestApp { app in
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123")
            try await app.makeUser(username: "bob", password: "bob-password-12345")
            let aliceBookmark = try await app.makeBookmark(for: alice, url: "https://alice.com", tags: ["foo-bar"])

            let bob = try await app.login(username: "bob", password: "bob-password-12345")
            let result = try await rename(app, token: bob.accessToken, from: "foo-bar", to: "foobar")
            #expect(result?.affectedBookmarks == 0)

            let aliceTags = try await Bookmark.find(aliceBookmark.requireID(), on: app.db)?.tags
            #expect(aliceTags == ["foo-bar"])
        }
    }
}
