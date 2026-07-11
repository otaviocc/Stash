// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation
import Vapor

/// Bookmark CRUD, scoped to the authenticated user (PRD §9.3).
struct BookmarkController: RouteCollection {

    // MARK: Static Properties

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // MARK: Static Functions

    // MARK: - Helpers

    private static func parseISO8601(_ raw: String) -> Date? {
        iso8601Fractional.date(from: raw) ?? iso8601.date(from: raw)
    }

    private static func parseSince(_ req: Request) throws -> Date? {
        guard let raw = req.query[String.self, at: "since"]?.nonEmpty else {
            return nil
        }
        guard let date = parseISO8601(raw) else {
            throw APIError.validationFailed("The 'since' parameter must be a valid ISO-8601 date.")
        }

        return date
    }

    /// Parses the `(afterUpdatedAt, afterId)` keyset continuation. Both must be present together;
    /// absent → first page. `afterUpdatedAt` is parsed with fractional precision so the keyset
    /// boundary round-trips exactly (the response emits it fractional too).
    private static func parseAfter(_ req: Request) throws -> (updatedAt: Date, id: UUID)? {
        let rawDate = req.query[String.self, at: "afterUpdatedAt"]?.nonEmpty
        let rawID = req.query[String.self, at: "afterId"]?.nonEmpty

        guard rawDate != nil || rawID != nil else {
            return nil
        }
        guard let rawDate, let rawID, let date = parseISO8601(rawDate), let id = UUID(uuidString: rawID) else {
            throw APIError
                .validationFailed("'afterUpdatedAt' and 'afterId' must both be a valid ISO-8601 date and UUID.")
        }

        return (date, id)
    }

    // MARK: Functions

    func boot(routes: RoutesBuilder) throws {
        let bookmarks = routes.grouped("bookmarks")
        bookmarks.get(use: list)
        bookmarks.get("changes", use: changes)
        bookmarks.get("deleted", use: deleted)
        bookmarks.post(use: create)
        bookmarks.group(":bookmarkID") { bookmark in
            bookmark.get(use: get)
            bookmark.put(use: update)
            bookmark.delete(use: delete)
            bookmark.post("wayback", use: submitToWayback)
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
            builder.filterByTag(rawTag)
        }

        let result = try await builder
            .sort(\.$createdAt, .descending)
            .sort(\.$id, .descending)
            .paginate(PageRequest(page: page, per: per))

        let items = try result.items.map { try $0.asResponse() }
        return Page(items: items, metadata: result.metadata)
    }

    func changes(req: Request) async throws -> ChangesPage<BookmarkResponse> {
        let user = try req.auth.require(User.self)
        let since = try Self.parseSince(req)
        let after = try Self.parseAfter(req)
        let per = min(max(req.query[Int.self, at: "per"] ?? 100, 1), 500)

        let builder = try Bookmark.query(on: req.db)
            .filter(\.$user.$id == user.requireID())

        if let since {
            builder.filter(\.$updatedAt > since)
        }

        if let after {
            builder.group(.or) { group in
                group.filter(\.$updatedAt > after.updatedAt)
                group.group(.and) { tie in
                    tie.filter(\.$updatedAt == after.updatedAt)
                    tie.filter(\.$id > after.id)
                }
            }
        }

        let fetched = try await builder
            .sort(\.$updatedAt, .ascending)
            .sort(\.$id, .ascending)
            .range(..<(per + 1))
            .all()

        let hasMore = fetched.count > per
        let page = hasMore ? Array(fetched.prefix(per)) : fetched
        let items = try page.map { try $0.asResponse() }
        let last = hasMore ? page.last : nil

        return try ChangesPage(
            items: items,
            hasMore: hasMore,
            nextAfterUpdatedAt: last.map { Self.iso8601Fractional.string(from: $0.updatedAt ?? Date()) },
            nextAfterId: last.map { try $0.requireID() }
        )
    }

    func deleted(req: Request) async throws -> [DeletedBookmarkResponse] {
        let user = try req.auth.require(User.self)
        let since = try Self.parseSince(req)

        let builder = try DeletedBookmark.query(on: req.db)
            .filter(\.$userID == user.requireID())

        if let since {
            builder.filter(\.$deletedAt > since)
        }

        let records = try await builder
            .sort(\.$deletedAt, .ascending)
            .all()

        return records.map {
            DeletedBookmarkResponse(id: $0.bookmarkID, deletedAt: $0.deletedAt ?? Date())
        }
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
        var declaredIcon: String?

        if input.fetchMetadata ?? true {
            let fetched = await MetadataFetcher.fetch(url: url, on: req)
            title = title ?? fetched.title
            description = description ?? fetched.description
            declaredIcon = fetched.faviconURL
        }

        let bookmark = Bookmark(
            userID: userID,
            url: url,
            title: title ?? url,
            description: description,
            tags: Bookmark.normalizeTags(input.tags ?? []),
            isArchived: input.isArchived ?? false
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
        req.logger.info("\(ActivityLog.bookmarkSaved(url: url, user: user.username))")

        FaviconFetcher.enqueue(forURL: url, declaredIconURL: declaredIcon, on: req.application)
        await WaybackSubmitter.enqueueIfAllowed(bookmark, for: user, on: req.application)

        let response = Response(status: .created)
        try response.content.encode(bookmark.asResponse())
        return response
    }

    func get(req: Request) async throws -> BookmarkResponse {
        try await requireBookmark(req).asResponse()
    }

    /// Submits (or re-submits, with a fresh date) a bookmark to the Wayback Machine, regardless of
    /// the user's `archiveNewBookmarks` auto-submit preference. Refused with `409` when the admin has
    /// turned the feature off instance-wide (PRD §9.7 admin toggle). Existence/ownership is checked
    /// first — a missing or foreign bookmark is always `404`, whether or not the feature is enabled,
    /// matching the OpenAPI contract and the web handler's ordering.
    func submitToWayback(req: Request) async throws -> Response {
        let bookmark = try await requireBookmark(req)

        guard WaybackSubmitter.isInstanceEnabled(on: req.application) else {
            throw APIError.custom(
                status: .conflict,
                code: "internet_archive_disabled",
                message: "Internet Archive submissions are disabled on this instance."
            )
        }

        await WaybackSubmitter.enqueue(bookmark, on: req.application)
        return Response(status: .accepted)
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
        if let title = input.title {
            bookmark.title = title
        }
        if let description = input.description {
            bookmark.description = description
        }
        if let tags = input.tags {
            bookmark.applyTags(Bookmark.normalizeTags(tags))
        }
        if let isArchived = input.isArchived {
            bookmark.isArchived = isArchived
        }

        try await bookmark.save(on: req.db)
        return try bookmark.asResponse()
    }

    func delete(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let bookmark = try await requireBookmark(req)
        let bookmarkID = try bookmark.requireID()
        let userID = try user.requireID()
        let url = bookmark.url

        try await req.db.transaction { db in
            try await bookmark.delete(on: db)
            try await DeletedBookmark.record(bookmarkID: bookmarkID, userID: userID, on: db)
        }

        user.bookmarkCount = max(user.bookmarkCount - 1, 0)
        try await user.save(on: req.db)
        req.logger.info("\(ActivityLog.bookmarkDeleted(url: url, user: user.username))")
        return Response(status: .noContent)
    }

    private func requireBookmark(_ req: Request) async throws -> Bookmark {
        let user = try req.auth.require(User.self)
        guard let id = req.parameters.get("bookmarkID", as: UUID.self),
              let bookmark = try await Bookmark.query(on: req.db)
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
