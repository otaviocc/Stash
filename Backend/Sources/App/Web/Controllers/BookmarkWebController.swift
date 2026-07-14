// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Vapor

/// The bookmark list (`GET /app`) and bookmark CRUD (`/app/bookmarks/*`) for the user-facing web
/// frontend. Session-cookie auth via `UserSessionMiddleware`; all data access is scoped to the
/// logged-in user. Presentation is delegated to `BookmarkPresenter` / `TagPresenter` and the shared
/// `AppSidebarLoader`.
struct BookmarkWebController: RouteCollection {

    func boot(routes: RoutesBuilder) throws {
        routes.get(use: list)

        let bookmarks = routes.grouped("bookmarks")
        bookmarks.get("new", use: newBookmarkForm)
        bookmarks.post(use: createBookmark)
        bookmarks.get(":bookmarkID", use: bookmarkDetail)
        bookmarks.get(":bookmarkID", "edit", use: editBookmarkForm)
        bookmarks.post(":bookmarkID", use: updateBookmark)
        bookmarks.post(":bookmarkID", "delete", use: deleteBookmark)
        bookmarks.post(":bookmarkID", "archive", use: archiveBookmark)
        bookmarks.post(":bookmarkID", "unarchive", use: unarchiveBookmark)
        bookmarks.post(":bookmarkID", "refresh-favicon", use: refreshFavicon)
        bookmarks.post(":bookmarkID", "save-to-wayback", use: saveToWayback)
    }

    // MARK: - List

    func list(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let query = try req.query.decode(BookmarkListQuery.self)

        let page = max(query.page ?? 1, 1)
        let per = WebPagination.perPage
        let archived = query.archived ?? false
        let boundaries = Bookmark.dateBoundaries()

        let builder = try Bookmark.query(on: req.db)
            .filter(\.$user.$id == user.requireID())
            .filter(\.$isArchived == archived)

        if let term = query.q?.nonEmpty {
            builder.filterFullText(term)
        }

        if let rawTag = query.tag?.nonEmpty {
            builder.filterByTag(rawTag, boundaries: boundaries)
        }

        let result = try await builder
            .sort(\.$createdAt, .descending)
            .sort(\.$id, .descending)
            .paginate(PageRequest(page: page, per: per))

        let total = result.metadata.total
        let pageCount = WebPagination.pageCount(total: total)

        let rawTag = query.tag?.nonEmpty
        let isUntagged = rawTag == Bookmark.untaggedSentinel
        let isToday = rawTag == Bookmark.todaySentinel
        let isThisWeek = rawTag == Bookmark.thisWeekSentinel
        let isSpecial = isUntagged || isToday || isThisWeek
        let activeTag = isSpecial ? "" : Bookmark.normalizeTagQuery(query.tag ?? "")
        let sidebar = try await AppSidebarLoader.load(
            for: user,
            activeTag: activeTag,
            activeSmartViewID: "",
            today: boundaries.today,
            week: boundaries.week,
            on: req.db
        )

        let tagDisplay: String =
            if isUntagged {
                "Untagged"
            } else if isToday {
                "Today"
            } else if isThisWeek {
                "This Week"
            } else {
                TagPresenter.display(rawTag ?? "")
            }

        return try await req.view.render("app-bookmarks", AppBookmarksContext(
            title: archived ? "Archived" : "Bookmarks",
            appUsername: user.username,
            appIsAdmin: user.role == .admin,
            bookmarks: result.items.map { try BookmarkPresenter.row(from: $0) },
            q: query.q?.nonEmpty ?? "",
            tag: rawTag ?? "",
            tagDisplay: tagDisplay,
            archived: archived,
            archiveToggleURL: BookmarkPresenter.archiveToggleURL(query, showArchived: !archived),
            total: total,
            page: page,
            pageCount: pageCount,
            prevURL: page > 1 ? BookmarkPresenter.listURL(query, page: page - 1) : nil,
            nextURL: page < pageCount ? BookmarkPresenter.listURL(query, page: page + 1) : nil,
            notice: FlashMessage.notice(for: req.query[String.self, at: "notice"]),
            sidebarTags: sidebar.tags,
            untaggedCount: sidebar.untaggedCount,
            untaggedActive: isUntagged,
            todayCount: sidebar.todayCount,
            todayActive: isToday,
            thisWeekCount: sidebar.thisWeekCount,
            thisWeekActive: isThisWeek,
            smartViews: sidebar.smartViews,
            isSmartView: false,
            smartViewID: "",
            showArchivedToggle: false,
            chrome: req.siteChrome()
        ))
    }

    // MARK: - Create

    func newBookmarkForm(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let url = req.query[String.self, at: "url"] ?? ""

        return try await req.view.render("app-bookmark-new", AppNewBookmarkContext(
            title: "Add bookmark", appUsername: user.username, appIsAdmin: user.role == .admin, error: nil,
            existingID: nil,
            url: url, bookmarkTitle: "", description: "", tags: "", previewed: false,
            knownTagsJSON: KnownTags.json(for: user, on: req.db),
            chrome: req.siteChrome()
        ))
    }

    func createBookmark(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let form = try req.content.decode(CreateBookmarkForm.self)

        let rawURL = form.url.trimmingCharacters(in: .whitespacesAndNewlines)
        var title = form.title?.nonEmpty
        var description = form.description?.nonEmpty
        let tagsText = form.tags ?? ""
        let tagsJSON = try await KnownTags.json(for: user, on: req.db)

        func renderForm(
            error: String?,
            existingID: String? = nil,
            status: HTTPResponseStatus = .ok,
            previewed: Bool = false
        ) async throws -> Response {
            try await req.renderHTML("app-bookmark-new", AppNewBookmarkContext(
                title: "Add bookmark", appUsername: user.username, appIsAdmin: user.role == .admin, error: error,
                existingID: existingID,
                url: rawURL, bookmarkTitle: title ?? "", description: description ?? "",
                tags: tagsText, previewed: previewed, knownTagsJSON: tagsJSON,
                chrome: req.siteChrome()
            ), status: status)
        }

        let url: String
        do {
            url = try Bookmark.validatedURL(rawURL)
        } catch {
            return try await renderForm(error: "Enter a valid http(s) URL.", status: .unprocessableEntity)
        }

        if form.action == "preview" {
            let fetched = await MetadataFetcher.fetch(url: url, on: req)
            title = title ?? fetched.title
            description = description ?? fetched.description
            return try await renderForm(error: nil, previewed: true)
        }

        let userID = try user.requireID()
        if let existing = try await existingBookmark(url: url, userID: userID, on: req.db) {
            return try await renderForm(
                error: "You've already saved this URL.",
                existingID: existing.requireID().uuidString,
                status: .conflict
            )
        }

        var declaredIcon: String?
        if title == nil || description == nil {
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
            tags: Bookmark.normalizeTags(fromFreeText: tagsText),
            isArchived: false
        )
        do {
            try await bookmark.save(on: req.db)
        } catch {
            if let existing = try await existingBookmark(url: url, userID: userID, on: req.db) {
                return try await renderForm(
                    error: "You've already saved this URL.",
                    existingID: existing.requireID().uuidString,
                    status: .conflict
                )
            }
            throw error
        }

        user.bookmarkCount += 1
        try await user.save(on: req.db)
        req.logger.info("\(ActivityLog.bookmarkSaved(url: url, user: user.username))")
        FaviconFetcher.enqueue(forURL: url, declaredIconURL: declaredIcon, on: req.application)
        await WaybackSubmitter.enqueueIfAllowed(bookmark, for: user, on: req.application)

        return try req.redirect(to: "/app/bookmarks/\(bookmark.requireID())?ok=created")
    }

    // MARK: - Detail / edit / update

    func bookmarkDetail(req: Request) async throws -> Response {
        guard let bookmark = try await loadBookmark(req) else { return req.redirect(to: "/app") }

        let message = FlashMessage.app(for: req.query[String.self, at: "ok"])
        let error = FlashMessage.appError(for: req.query[String.self, at: "error"])
        return try await req.renderHTML("app-bookmark-detail", AppBookmarkDetailContext(
            title: bookmark.title,
            appUsername: req.auth.require(User.self).username,
            appIsAdmin: req.auth.require(User.self).role == .admin,
            bookmark: BookmarkPresenter.row(from: bookmark),
            message: message,
            error: error,
            chrome: req.siteChrome()
        ))
    }

    func editBookmarkForm(req: Request) async throws -> Response {
        guard let bookmark = try await loadBookmark(req) else { return req.redirect(to: "/app") }

        return try await renderEdit(req, bookmark: bookmark, error: nil)
    }

    func updateBookmark(req: Request) async throws -> Response {
        guard let bookmark = try await loadBookmark(req) else { return req.redirect(to: "/app") }

        let form = try req.content.decode(EditBookmarkForm.self)

        bookmark.title = form.title?.nonEmpty ?? bookmark.url
        bookmark.description = form.description?.nonEmpty
        bookmark.applyTags(Bookmark.normalizeTags(fromFreeText: form.tags ?? ""))
        try await bookmark.save(on: req.db)
        return try req.redirect(to: "/app/bookmarks/\(bookmark.requireID())?ok=saved")
    }

    func deleteBookmark(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        guard let bookmark = try await loadBookmark(req) else { return req.redirect(to: "/app") }

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
        return req.redirect(to: "/app")
    }

    func archiveBookmark(req: Request) async throws -> Response {
        try await setArchived(req, true)
    }

    func unarchiveBookmark(req: Request) async throws -> Response {
        try await setArchived(req, false)
    }

    func refreshFavicon(req: Request) async throws -> Response {
        guard let bookmark = try await loadBookmark(req) else { return req.redirect(to: "/app") }

        if let domain = DomainExtractor.domain(from: bookmark.url) {
            try await FaviconFetcher.refresh(domain: domain, on: req.application)
        }

        return try req.redirect(to: "/app/bookmarks/\(bookmark.requireID())?ok=favicon_refreshing")
    }

    func saveToWayback(req: Request) async throws -> Response {
        guard let bookmark = try await loadBookmark(req) else { return req.redirect(to: "/app") }
        guard WaybackSubmitter.isInstanceEnabled(on: req.application) else {
            return try req.redirect(to: "/app/bookmarks/\(bookmark.requireID())?error=internet_archive_disabled")
        }

        await WaybackSubmitter.enqueue(bookmark, on: req.application)

        return try req.redirect(to: "/app/bookmarks/\(bookmark.requireID())?ok=wayback_started")
    }

    // MARK: - Helpers

    private func loadBookmark(_ req: Request) async throws -> Bookmark? {
        let user = try req.auth.require(User.self)
        guard let id = req.parameters.get("bookmarkID", as: UUID.self) else { return nil }

        return try await Bookmark.query(on: req.db)
            .filter(\.$user.$id == user.requireID())
            .filter(\.$id == id)
            .first()
    }

    private func existingBookmark(url: String, userID: User.IDValue, on db: Database) async throws -> Bookmark? {
        try await Bookmark.query(on: db)
            .filter(\.$user.$id == userID)
            .filter(\.$url == url)
            .first()
    }

    private func setArchived(_ req: Request, _ archived: Bool) async throws -> Response {
        guard let bookmark = try await loadBookmark(req) else { return req.redirect(to: "/app") }

        bookmark.isArchived = archived
        try await bookmark.save(on: req.db)
        return try req.redirect(to: "/app/bookmarks/\(bookmark.requireID())?ok=\(archived ? "archived" : "unarchived")")
    }

    private func renderEdit(_ req: Request, bookmark: Bookmark, error: String?) async throws -> Response {
        let user = try req.auth.require(User.self)
        return try await req.renderHTML("app-bookmark-edit", AppEditBookmarkContext(
            title: "Edit",
            appUsername: user.username,
            appIsAdmin: user.role == .admin,
            error: error,
            id: bookmark.requireID().uuidString,
            url: bookmark.url,
            bookmarkTitle: bookmark.title,
            description: bookmark.description ?? "",
            tags: bookmark.tags.joined(separator: ", "),
            knownTagsJSON: KnownTags.json(for: user, on: req.db),
            chrome: req.siteChrome()
        ))
    }
}
