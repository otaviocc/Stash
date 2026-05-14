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
import Vapor

/// Bookmark CRUD, scoped to the authenticated user (PRD §9.3).
struct BookmarkController: RouteCollection {

    func boot(routes: RoutesBuilder) throws {
        let bookmarks = routes.grouped("bookmarks")
        bookmarks.get(use: list)
        bookmarks.post(use: create)
        bookmarks.group(":bookmarkID") { bookmark in
            bookmark.get(use: get)
            bookmark.put(use: update)
            bookmark.delete(use: delete)
        }
    }

    func list(req: Request) async throws -> Page<BookmarkResponse> {
        let user = try req.auth.require(User.self)
        let query = try req.query.decode(BookmarkListQuery.self)

        let page = max(query.page ?? 1, 1)
        let per = min(max(query.per ?? 20, 1), 100)

        let builder = try Bookmark.query(on: req.db)
            .filter(\.$user.$id == user.requireID())
            .filter(\.$isArchived == (query.archived ?? false))

        if let term = query.q?.nonEmpty {
            builder.filterFullText(term)
        }

        if let rawTag = query.tag?.nonEmpty {
            let tag = Bookmark.normalizeTagQuery(rawTag)
            if !tag.isEmpty {
                builder.group(.or) { group in
                    group.filter(\.$tagsSearch ~~ "|\(tag)|")
                    group.filter(\.$tagsSearch ~~ "|\(tag)/")
                }
            }
        }

        let result = try await builder
            .sort(\.$createdAt, .descending)
            .sort(\.$id, .descending)
            .paginate(PageRequest(page: page, per: per))

        let items = try result.items.map { try $0.asResponse() }
        return Page(items: items, metadata: result.metadata)
    }

    func create(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let input = try req.content.decode(CreateBookmarkInput.self)
        let url = try Bookmark.validatedURL(input.url)
        let userID = try user.requireID()

        if let existing = try await existingBookmark(url: url, userID: userID, on: req.db) {
            throw try APIError.duplicateURL(existingID: existing.requireID())
        }

        var title = input.title?.nonEmpty
        var description = input.description?.nonEmpty
        var faviconURL: String?

        if input.fetchMetadata ?? true {
            let fetched = await MetadataFetcher.fetch(url: url, on: req)
            title = title ?? fetched.title
            description = description ?? fetched.description
            faviconURL = fetched.faviconURL
        }

        let bookmark = Bookmark(
            userID: userID,
            url: url,
            title: title ?? url,
            description: description,
            faviconURL: faviconURL,
            tags: Bookmark.normalizeTags(input.tags ?? []),
            isArchived: false
        )

        do {
            try await bookmark.save(on: req.db)
        } catch {
            if let existing = try await existingBookmark(url: url, userID: userID, on: req.db) {
                throw try APIError.duplicateURL(existingID: existing.requireID())
            }
            throw error
        }

        user.bookmarkCount += 1
        try await user.save(on: req.db)

        let response = Response(status: .created)
        try response.content.encode(bookmark.asResponse())
        return response
    }

    func get(req: Request) async throws -> BookmarkResponse {
        try await requireBookmark(req).asResponse()
    }

    func update(req: Request) async throws -> BookmarkResponse {
        let user = try req.auth.require(User.self)
        let bookmark = try await requireBookmark(req)
        let input = try req.content.decode(UpdateBookmarkInput.self)

        if let rawURL = input.url {
            let url = try Bookmark.validatedURL(rawURL)
            if url != bookmark.url {
                if let existing = try await existingBookmark(url: url, userID: user.requireID(), on: req.db),
                   try existing.requireID() != bookmark.requireID()
                {
                    throw try APIError.duplicateURL(existingID: existing.requireID())
                }
                bookmark.url = url
            }
        }
        if let title = input.title { bookmark.title = title }
        if let description = input.description { bookmark.description = description }
        if let tags = input.tags { bookmark.applyTags(Bookmark.normalizeTags(tags)) }
        if let isArchived = input.isArchived { bookmark.isArchived = isArchived }

        try await bookmark.save(on: req.db)
        return try bookmark.asResponse()
    }

    func delete(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let bookmark = try await requireBookmark(req)
        try await bookmark.delete(on: req.db)

        user.bookmarkCount = max(user.bookmarkCount - 1, 0)
        try await user.save(on: req.db)
        return Response(status: .noContent)
    }

    // MARK: - Helpers

    private func requireBookmark(_ req: Request) async throws -> Bookmark {
        let user = try req.auth.require(User.self)
        guard let id = req.parameters.get("bookmarkID", as: UUID.self) else {
            throw APIError.notFound
        }
        guard let bookmark = try await Bookmark.query(on: req.db)
            .filter(\.$user.$id == user.requireID())
            .filter(\.$id == id)
            .first()
        else {
            throw APIError.notFound
        }

        return bookmark
    }

    private func existingBookmark(url: String, userID: User.IDValue, on db: Database) async throws -> Bookmark? {
        try await Bookmark.query(on: db)
            .filter(\.$user.$id == userID)
            .filter(\.$url == url)
            .first()
    }
}
