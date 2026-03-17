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
import Vapor
import VaporTesting
@testable import App

// MARK: - SmartViewTests

/// Verifies Smart View CRUD, condition validation, live query execution (AND semantics), and
/// per-user isolation.
@Suite("Smart Views — CRUD, validation, query execution, isolation")
struct SmartViewTests {

    @Test("create returns 201 and the Smart View with its conditions")
    func create() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            // When
            try await app.testing().test(
                .POST, "api/v1/smart-views",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(SmartViewRequestBody(
                        name: "YouTube Reviews",
                        conditions: [
                            SmartViewConditionPayload(type: "urlContains", value: "youtube"),
                            SmartViewConditionPayload(type: "titleContains", value: "review")
                        ]
                    ))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .created, "It should return 201 Created")
                    let view = try res.content.decode(SmartViewResponse.self)
                    #expect(view.name == "YouTube Reviews", "It should store the submitted name")
                    #expect(view.conditions.count == 2, "It should store both conditions")
                    #expect(view.conditions.first?.type == "urlContains", "It should preserve the condition type")
                    #expect(view.conditions.first?.value == "youtube", "It should preserve the condition value")
                }
            )
        }
    }

    @Test("create with an empty name returns 422")
    func createEmptyName() async throws {
        try await withTestApp { app in
            try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            try await app.testing().test(
                .POST, "api/v1/smart-views",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(SmartViewRequestBody(
                        name: "  ",
                        conditions: [SmartViewConditionPayload(type: "tag", value: "swift")]
                    ))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unprocessableEntity, "It should return 422")
                    #expect(
                        try res.content.decode(TestError.self).code == "validation_failed",
                        "It should return the validation_failed error code"
                    )
                }
            )
        }
    }

    @Test("create with no conditions returns 422")
    func createNoConditions() async throws {
        try await withTestApp { app in
            try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            try await app.testing().test(
                .POST, "api/v1/smart-views",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(SmartViewRequestBody(name: "Empty", conditions: []))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unprocessableEntity, "It should return 422 with no conditions")
                    #expect(
                        try res.content.decode(TestError.self).code == "validation_failed",
                        "It should fail validation"
                    )
                }
            )
        }
    }

    @Test("create with an unknown condition type returns 422")
    func createUnknownType() async throws {
        try await withTestApp { app in
            try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            try await app.testing().test(
                .POST, "api/v1/smart-views",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(SmartViewRequestBody(
                        name: "Bad",
                        conditions: [SmartViewConditionPayload(type: "favoriteColor", value: "blue")]
                    ))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unprocessableEntity, "It should reject an unknown condition type")
                    #expect(
                        try res.content.decode(TestError.self).code == "validation_failed",
                        "It should fail validation"
                    )
                }
            )
        }
    }

    @Test("create with an empty condition value returns 422")
    func createEmptyValue() async throws {
        try await withTestApp { app in
            try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            try await app.testing().test(
                .POST, "api/v1/smart-views",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(SmartViewRequestBody(
                        name: "Bad",
                        conditions: [SmartViewConditionPayload(type: "tag", value: "  ")]
                    ))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unprocessableEntity, "It should reject an empty condition value")
                    #expect(
                        try res.content.decode(TestError.self).code == "validation_failed",
                        "It should fail validation"
                    )
                }
            )
        }
    }

    @Test("a tag condition matches the tag and its descendants (prefix)")
    func tagCondition() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await app.makeBookmark(for: user, url: "https://1.com", tags: ["swift"])
            try await app.makeBookmark(for: user, url: "https://2.com", tags: ["swift/vapor"])
            try await app.makeBookmark(for: user, url: "https://3.com", tags: ["swiftui"])
            let view = try await app.makeSmartView(
                token: pair.accessToken,
                name: "Swift",
                conditions: [SmartViewConditionPayload(type: "tag", value: "swift")]
            )

            // When
            try await app.testing().test(
                .GET, "api/v1/smart-views/\(view.id)/bookmarks",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(
                    Set(page.items.map(\.url)) == ["https://1.com", "https://2.com"],
                    "It should match the tag and its descendants but not unrelated tags"
                )
            }
        }
    }

    @Test("a urlContains condition matches case-insensitively")
    func urlContainsCondition() async throws {
        try await withTestApp { app in
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await app.makeBookmark(for: user, url: "https://www.YouTube.com/watch")
            try await app.makeBookmark(for: user, url: "https://example.com")
            let view = try await app.makeSmartView(
                token: pair.accessToken,
                name: "YT",
                conditions: [SmartViewConditionPayload(type: "urlContains", value: "youtube")]
            )

            try await app.testing().test(
                .GET, "api/v1/smart-views/\(view.id)/bookmarks",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(
                    page.items.map(\.url) == ["https://www.YouTube.com/watch"],
                    "It should match the URL case-insensitively"
                )
            }
        }
    }

    @Test("a titleContains condition returns the matching bookmarks")
    func titleContainsCondition() async throws {
        try await withTestApp { app in
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await app.makeBookmark(for: user, url: "https://1.com", title: "A great Review of things")
            try await app.makeBookmark(for: user, url: "https://2.com", title: "Unrelated")
            let view = try await app.makeSmartView(
                token: pair.accessToken,
                name: "Reviews",
                conditions: [SmartViewConditionPayload(type: "titleContains", value: "review")]
            )

            try await app.testing().test(
                .GET, "api/v1/smart-views/\(view.id)/bookmarks",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(page.items.map(\.url) == ["https://1.com"], "It should match on the title")
            }
        }
    }

    @Test("a contains condition treats LIKE metacharacters as literal text")
    func containsEscapesWildcards() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await app.makeBookmark(for: user, url: "https://1.com", title: "100% organic")
            try await app.makeBookmark(for: user, url: "https://2.com", title: "100 dollars")
            let view = try await app.makeSmartView(
                token: pair.accessToken,
                name: "Literal percent",
                conditions: [SmartViewConditionPayload(type: "titleContains", value: "100%")]
            )

            // When
            try await app.testing().test(
                .GET, "api/v1/smart-views/\(view.id)/bookmarks",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(
                    page.items.map(\.url) == ["https://1.com"],
                    "It should match the literal '%' and not treat it as a wildcard that also matches '100 dollars'"
                )
            }
        }
    }

    @Test("a createdAfter condition returns only newer bookmarks")
    func createdAfterCondition() async throws {
        try await withTestApp { app in
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let old = try await app.makeBookmark(for: user, url: "https://old.com")
            old.createdAt = Date(timeIntervalSince1970: 0)
            try await old.save(on: app.db)
            try await app.makeBookmark(for: user, url: "https://new.com")
            let view = try await app.makeSmartView(
                token: pair.accessToken,
                name: "Recent",
                conditions: [SmartViewConditionPayload(type: "createdAfter", value: "2000-01-01T00:00:00Z")]
            )

            try await app.testing().test(
                .GET, "api/v1/smart-views/\(view.id)/bookmarks",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(page.items.map(\.url) == ["https://new.com"], "It should return only the newer bookmark")
            }
        }
    }

    @Test("an isArchived:true condition returns archived bookmarks")
    func isArchivedCondition() async throws {
        try await withTestApp { app in
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await app.makeBookmark(for: user, url: "https://active.com", isArchived: false)
            try await app.makeBookmark(for: user, url: "https://archived.com", isArchived: true)
            let view = try await app.makeSmartView(
                token: pair.accessToken,
                name: "Archived",
                conditions: [SmartViewConditionPayload(type: "isArchived", value: "true")]
            )

            try await app.testing().test(
                .GET, "api/v1/smart-views/\(view.id)/bookmarks",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(
                    page.items.map(\.url) == ["https://archived.com"],
                    "It should override the default filter and return archived bookmarks"
                )
            }
        }
    }

    @Test("a hasTags condition filters on whether a bookmark has any tags")
    func hasTagsCondition() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await app.makeBookmark(for: user, url: "https://tagged.com", tags: ["swift"])
            try await app.makeBookmark(for: user, url: "https://untagged.com", tags: [])
            let untaggedView = try await app.makeSmartView(
                token: pair.accessToken,
                name: "Untagged",
                conditions: [SmartViewConditionPayload(type: "hasTags", value: "false")]
            )
            let taggedView = try await app.makeSmartView(
                token: pair.accessToken,
                name: "Tagged",
                conditions: [SmartViewConditionPayload(type: "hasTags", value: "true")]
            )

            // When / Then
            try await app.testing().test(
                .GET, "api/v1/smart-views/\(untaggedView.id)/bookmarks",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(
                    page.items.map(\.url) == ["https://untagged.com"],
                    "It should return only bookmarks with no tags when hasTags is false"
                )
            }

            try await app.testing().test(
                .GET, "api/v1/smart-views/\(taggedView.id)/bookmarks",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(
                    page.items.map(\.url) == ["https://tagged.com"],
                    "It should return only bookmarks with at least one tag when hasTags is true"
                )
            }
        }
    }

    @Test("hasTags combines with another condition (untagged AND url contains)")
    func hasTagsCombinedWithUrl() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await app.makeBookmark(for: user, url: "https://wwdc.io/untagged", tags: [])
            try await app.makeBookmark(for: user, url: "https://wwdc.io/tagged", tags: ["video"])
            try await app.makeBookmark(for: user, url: "https://example.com/untagged", tags: [])
            let view = try await app.makeSmartView(
                token: pair.accessToken,
                name: "Untagged WWDC",
                conditions: [
                    SmartViewConditionPayload(type: "hasTags", value: "false"),
                    SmartViewConditionPayload(type: "urlContains", value: "wwdc")
                ]
            )

            // When
            try await app.testing().test(
                .GET, "api/v1/smart-views/\(view.id)/bookmarks",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(
                    page.items.map(\.url) == ["https://wwdc.io/untagged"],
                    "It should return only the untagged bookmark whose URL also contains 'wwdc'"
                )
            }
        }
    }

    @Test("an invalid hasTags value returns 422")
    func invalidHasTags() async throws {
        try await withTestApp { app in
            try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            try await app.testing().test(
                .POST, "api/v1/smart-views",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(SmartViewRequestBody(
                        name: "Bad",
                        conditions: [SmartViewConditionPayload(type: "hasTags", value: "maybe")]
                    ))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unprocessableEntity, "It should reject a non-boolean hasTags value")
                    #expect(
                        try res.content.decode(TestError.self).code == "validation_failed",
                        "It should fail validation"
                    )
                }
            )
        }
    }

    @Test("multiple conditions must all match (AND)")
    func multipleConditionsAreAnded() async throws {
        try await withTestApp { app in
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await app.makeBookmark(for: user, url: "https://youtube.com/a", title: "A great review")
            try await app.makeBookmark(for: user, url: "https://youtube.com/b", title: "Just a video")
            try await app.makeBookmark(for: user, url: "https://vimeo.com/c", title: "Another review")
            let view = try await app.makeSmartView(
                token: pair.accessToken,
                name: "YT Reviews",
                conditions: [
                    SmartViewConditionPayload(type: "urlContains", value: "youtube"),
                    SmartViewConditionPayload(type: "titleContains", value: "review")
                ]
            )

            try await app.testing().test(
                .GET, "api/v1/smart-views/\(view.id)/bookmarks",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(
                    page.items.map(\.url) == ["https://youtube.com/a"],
                    "It should return only the bookmark matching both"
                )
            }
        }
    }

    @Test("two tag conditions require the bookmark to have both tags")
    func twoTagConditions() async throws {
        try await withTestApp { app in
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await app.makeBookmark(for: user, url: "https://both.com", tags: ["swift", "ios"])
            try await app.makeBookmark(for: user, url: "https://one.com", tags: ["swift"])
            let view = try await app.makeSmartView(
                token: pair.accessToken,
                name: "Swift+iOS",
                conditions: [
                    SmartViewConditionPayload(type: "tag", value: "swift"),
                    SmartViewConditionPayload(type: "tag", value: "ios")
                ]
            )

            try await app.testing().test(
                .GET, "api/v1/smart-views/\(view.id)/bookmarks",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(page.items.map(\.url) == ["https://both.com"], "It should require both tags")
            }
        }
    }

    @Test("a user cannot access another user's Smart View or its bookmarks (404)")
    func userIsolation() async throws {
        try await withTestApp { app in
            let alice = try await app.makeUser(username: "alice", password: "alice-password-1234")
            try await app.makeUser(username: "bob", password: "bob-password-12345")
            let alicePair = try await app.login(username: "alice", password: "alice-password-1234")
            try await app.makeBookmark(for: alice, url: "https://alice.com", tags: ["swift"])
            let view = try await app.makeSmartView(
                token: alicePair.accessToken,
                name: "Alice's",
                conditions: [SmartViewConditionPayload(type: "tag", value: "swift")]
            )

            let bob = try await app.login(username: "bob", password: "bob-password-12345")

            try await app.testing().test(
                .GET, "api/v1/smart-views/\(view.id)",
                headers: bearer(bob.accessToken)
            ) { res async throws in
                #expect(res.status == .notFound, "It should hide another user's Smart View")
                #expect(
                    try res.content.decode(TestError.self).code == "smart_view_not_found",
                    "It should return the smart_view_not_found error code"
                )
            }

            try await app.testing().test(
                .GET, "api/v1/smart-views/\(view.id)/bookmarks",
                headers: bearer(bob.accessToken)
            ) { res async throws in
                #expect(res.status == .notFound, "It should not run another user's Smart View")
            }
        }
    }

    @Test("delete removes the Smart View; a subsequent GET returns 404")
    func delete() async throws {
        try await withTestApp { app in
            try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let view = try await app.makeSmartView(
                token: pair.accessToken,
                name: "Temp",
                conditions: [SmartViewConditionPayload(type: "tag", value: "swift")]
            )

            try await app.testing().test(
                .DELETE, "api/v1/smart-views/\(view.id)",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                #expect(res.status == .noContent, "It should return 204 No Content")
            }

            try await app.testing().test(
                .GET, "api/v1/smart-views/\(view.id)",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                #expect(res.status == .notFound, "It should return 404 for the deleted Smart View")
            }
        }
    }

    @Test("matchMode 'any' returns the union of the conditions (OR)")
    func anyModeIsOr() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await app.makeBookmark(for: user, url: "https://youtube.com/x", title: "Plain video")
            try await app.makeBookmark(for: user, url: "https://vimeo.com/y", title: "A review")
            try await app.makeBookmark(for: user, url: "https://example.com/z", title: "Unrelated")
            let view = try await app.makeSmartView(
                token: pair.accessToken,
                name: "YT or reviews",
                conditions: [
                    SmartViewConditionPayload(type: "urlContains", value: "youtube"),
                    SmartViewConditionPayload(type: "titleContains", value: "review")
                ],
                matchMode: "any"
            )

            // When
            try await app.testing().test(
                .GET, "api/v1/smart-views/\(view.id)/bookmarks",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(
                    Set(page.items.map(\.url)) == ["https://youtube.com/x", "https://vimeo.com/y"],
                    "It should return bookmarks matching either condition, not only those matching both"
                )
            }
        }
    }

    @Test("matchMode defaults to 'all' when omitted")
    func matchModeDefaultsToAll() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await app.makeBookmark(for: user, url: "https://youtube.com/x", title: "A review")
            try await app.makeBookmark(for: user, url: "https://youtube.com/y", title: "Plain video")

            // When
            var created: SmartViewResponse?
            try await app.testing().test(
                .POST, "api/v1/smart-views",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(SmartViewRequestBody(
                        name: "No mode",
                        conditions: [
                            SmartViewConditionPayload(type: "urlContains", value: "youtube"),
                            SmartViewConditionPayload(type: "titleContains", value: "review")
                        ]
                    ))
                },
                afterResponse: { res async throws in created = try res.content.decode(SmartViewResponse.self) }
            )
            let view = try #require(created)

            // Then
            #expect(view.matchMode == "all", "It should default the match mode to 'all'")
            try await app.testing().test(
                .GET, "api/v1/smart-views/\(view.id)/bookmarks",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(
                    page.items.map(\.url) == ["https://youtube.com/x"],
                    "It should AND the conditions by default (only the bookmark matching both)"
                )
            }
        }
    }

    @Test("an invalid matchMode returns 422")
    func invalidMatchMode() async throws {
        try await withTestApp { app in
            try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            try await app.testing().test(
                .POST, "api/v1/smart-views",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(SmartViewRequestBody(
                        name: "Bad mode",
                        conditions: [SmartViewConditionPayload(type: "tag", value: "swift")],
                        matchMode: "sometimes"
                    ))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unprocessableEntity, "It should reject an unknown match mode")
                    #expect(
                        try res.content.decode(TestError.self).code == "validation_failed",
                        "It should fail validation"
                    )
                }
            )
        }
    }

    @Test("update changes the name, conditions, and matchMode")
    func updateChangesMatchMode() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await app.makeBookmark(for: user, url: "https://youtube.com/a", title: "plain")
            try await app.makeBookmark(for: user, url: "https://vimeo.com/b", title: "a review")
            let view = try await app.makeSmartView(
                token: pair.accessToken,
                name: "Original",
                conditions: [SmartViewConditionPayload(type: "urlContains", value: "youtube")],
                matchMode: "all"
            )

            // When
            try await app.testing().test(
                .PUT, "api/v1/smart-views/\(view.id)",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(SmartViewRequestBody(
                        name: "Renamed",
                        conditions: [
                            SmartViewConditionPayload(type: "urlContains", value: "youtube"),
                            SmartViewConditionPayload(type: "titleContains", value: "review")
                        ],
                        matchMode: "any"
                    ))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .ok, "It should return 200 OK")
                    let updated = try res.content.decode(SmartViewResponse.self)
                    #expect(updated.name == "Renamed", "It should update the name")
                    #expect(updated.matchMode == "any", "It should update the match mode")
                    #expect(updated.conditions.count == 2, "It should update the conditions")
                }
            )

            try await app.testing().test(
                .GET, "api/v1/smart-views/\(view.id)/bookmarks",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(
                    Set(page.items.map(\.url)) == ["https://youtube.com/a", "https://vimeo.com/b"],
                    "It should run the updated 'any' query (OR) after the update"
                )
            }
        }
    }

    @Test("update without a matchMode preserves the existing value")
    func updatePreservesMatchModeWhenOmitted() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let view = try await app.makeSmartView(
                token: pair.accessToken,
                name: "Any view",
                conditions: [SmartViewConditionPayload(type: "tag", value: "swift")],
                matchMode: "any"
            )

            // When — a PUT body that omits matchMode entirely
            try await app.testing().test(
                .PUT, "api/v1/smart-views/\(view.id)",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(SmartViewRequestBody(
                        name: "Renamed",
                        conditions: [SmartViewConditionPayload(type: "tag", value: "swift")]
                    ))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .ok, "It should return 200 OK")
                    let updated = try res.content.decode(SmartViewResponse.self)
                    #expect(updated.name == "Renamed", "It should apply the other changes")
                    #expect(
                        updated.matchMode == "any",
                        "It should keep the existing match mode when the body omits it"
                    )
                }
            )
        }
    }

    @Test("matchMode 'any' still excludes archived bookmarks without an isArchived condition")
    func anyModeRespectsArchivedDefault() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await app.makeBookmark(for: user, url: "https://active.com", tags: ["swift"], isArchived: false)
            try await app.makeBookmark(for: user, url: "https://archived.com", tags: ["swift"], isArchived: true)
            let view = try await app.makeSmartView(
                token: pair.accessToken,
                name: "Any swift",
                conditions: [
                    SmartViewConditionPayload(type: "tag", value: "swift"),
                    SmartViewConditionPayload(type: "titleContains", value: "nothing")
                ],
                matchMode: "any"
            )

            // When
            try await app.testing().test(
                .GET, "api/v1/smart-views/\(view.id)/bookmarks",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(
                    page.items.map(\.url) == ["https://active.com"],
                    "It should apply the non-archived default as an outer AND in 'any' mode"
                )
            }
        }
    }
}

extension Application {

    func makeSmartView(
        token: String,
        name: String,
        conditions: [SmartViewConditionPayload],
        matchMode: String = "all"
    ) async throws -> SmartViewResponse {
        var result: SmartViewResponse?
        try await testing().test(
            .POST, "api/v1/smart-views",
            headers: bearer(token),
            beforeRequest: { req in
                try req.content.encode(SmartViewRequestBody(name: name, conditions: conditions, matchMode: matchMode))
            },
            afterResponse: { res async throws in
                result = try res.content.decode(SmartViewResponse.self)
            }
        )
        guard let result else {
            throw Abort(.internalServerError, reason: "smart view creation did not return a response")
        }

        return result
    }
}
