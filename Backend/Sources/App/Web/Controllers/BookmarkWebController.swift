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
        let isSpecial = Bookmark.isSentinelTag(rawTag ?? "")
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
            returnToParam: TagPresenter.queryValue(BookmarkPresenter.listURL(query, page: page)),
            chrome: req.siteChrome()
        ))
    }

    // MARK: - Create

    func newBookmarkForm(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let url = req.query[String.self, at: "url"] ?? ""
        let (returnURL, returnToParam) = newBookmarkReturnContext(req)

        return try await req.view.render("app-bookmark-new", AppNewBookmarkContext(
            title: "Add bookmark", appUsername: user.username, appIsAdmin: user.role == .admin, error: nil,
            existingID: nil,
            url: url, bookmarkTitle: "", description: "", tags: tagFromReturnURL(returnURL), previewed: false,
            knownTagsJSON: KnownTags.json(for: user, on: req.db),
            returnURL: returnURL,
            returnToParam: returnToParam,
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
        let (returnURL, returnToParam) = returnContext(req)

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
                returnURL: returnURL,
                returnToParam: returnToParam,
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

        return try detailRedirect(req, id: bookmark.requireID(), ok: "created")
    }

    // MARK: - Detail / edit / update

    func bookmarkDetail(req: Request) async throws -> Response {
        guard let bookmark = try await loadBookmark(req) else { return req.redirect(to: "/app") }

        let message = FlashMessage.app(for: req.query[String.self, at: "ok"])
        let error = FlashMessage.appError(for: req.query[String.self, at: "error"])
        let (returnURL, returnToParam) = returnContext(req)
        return try await req.renderHTML("app-bookmark-detail", AppBookmarkDetailContext(
            title: bookmark.title,
            appUsername: req.auth.require(User.self).username,
            appIsAdmin: req.auth.require(User.self).role == .admin,
            bookmark: BookmarkPresenter.row(from: bookmark),
            message: message,
            error: error,
            returnURL: returnURL,
            returnToParam: returnToParam,
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
        return try detailRedirect(req, id: bookmark.requireID(), ok: "saved")
    }

    func deleteBookmark(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        guard let bookmark = try await loadBookmark(req) else { return req.redirect(to: "/app") }

        let bookmarkID = try bookmark.requireID()
        let userID = try user.requireID()
        let url = bookmark.url
        let returnURL = safeReturnTo(req)

        try await req.db.transaction { db in
            try await bookmark.delete(on: db)
            try await DeletedBookmark.record(bookmarkID: bookmarkID, userID: userID, on: db)
        }
        user.bookmarkCount = max(user.bookmarkCount - 1, 0)
        try await user.save(on: req.db)
        req.logger.info("\(ActivityLog.bookmarkDeleted(url: url, user: user.username))")
        return req.redirect(to: returnURL)
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

        return try detailRedirect(req, id: bookmark.requireID(), ok: "favicon_refreshing")
    }

    func saveToWayback(req: Request) async throws -> Response {
        guard let bookmark = try await loadBookmark(req) else { return req.redirect(to: "/app") }
        guard WaybackSubmitter.isInstanceEnabled(on: req.application) else {
            return try detailRedirect(req, id: bookmark.requireID(), error: "internet_archive_disabled")
        }

        await WaybackSubmitter.enqueue(bookmark, on: req.application)

        return try detailRedirect(req, id: bookmark.requireID(), ok: "wayback_started")
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
        return try detailRedirect(req, id: bookmark.requireID(), ok: archived ? "archived" : "unarchived")
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
            returnToParam: returnContext(req).param,
            chrome: req.siteChrome()
        ))
    }

    /// The validated return URL alongside its pre-encoded form for embedding as a query value —
    /// every context that renders a "back to the list" link needs both.
    private func returnContext(_ req: Request) -> (url: String, param: String) {
        let url = safeReturnTo(req)
        return (url, TagPresenter.queryValue(url))
    }

    /// The active tag to pre-fill on the "Add bookmark" form, derived from a `returnTo` list URL
    /// (e.g. `/app?tag=swift`). Empty when the return URL has no `tag` (a Smart View, or unfiltered
    /// `/app`) or names one of the synthetic sentinel filters, none of which are real tags.
    private func tagFromReturnURL(_ returnURL: String) -> String {
        guard let tag = URLComponents(string: returnURL)?.queryItems?.first(where: { $0.name == "tag" })?.value,
              !Bookmark.isSentinelTag(tag)
        else {
            return ""
        }

        return Bookmark.normalizeTagQuery(tag)
    }

    /// Validates a `returnTo` candidate: it must be a local `/app` path with no embedded control
    /// characters, so it's safe to use as a redirect target. Requires an exact `/app` match or a
    /// `/`-or-`?`-bounded prefix (not just `hasPrefix("/app")`) so a future route merely starting with
    /// those four characters (e.g. `/appearance`) can't be mistaken for this one. There's no need to
    /// separately reject `//` or `://`, since a same-origin `/app`-rooted path can never be absolute or
    /// protocol-relative — doing so previously rejected legitimate paths whose search query happened to
    /// contain `://` (e.g. `?q=https://example.com`). Checks `unicodeScalars` rather than `Character`s
    /// for the CR/LF scan: Swift merges `"\r\n"` into a single extended grapheme cluster, so a
    /// `Character`-based `contains("\r")` silently misses a CR immediately followed by an LF.
    private func validReturnTo(_ candidate: String?) -> String {
        guard let candidate,
              candidate == "/app" || candidate.hasPrefix("/app/") || candidate.hasPrefix("/app?"),
              !candidate.unicodeScalars.contains(where: { $0 == "\r" || $0 == "\n" })
        else {
            return "/app"
        }

        return candidate
    }

    /// The `returnTo` query param, validated — every handler except `newBookmarkForm` uses this. No
    /// `Referer` fallback here: once a request carries no explicit `returnTo` (e.g. a detail-page
    /// action's redirect target), `Referer` for the *next* request would just be that same page's own
    /// prior URL — a self-referential loop, not the originating list. See `newBookmarkReturnContext`.
    private func safeReturnTo(_ req: Request) -> String {
        validReturnTo(req.query[String.self, at: "returnTo"])
    }

    /// Return context for the "Add bookmark" page specifically: the explicit `returnTo` query param
    /// if present, else a same-origin path+query parsed from the `Referer` header — the global nav
    /// "Add" link is a plain same-origin click with no explicit param of its own, so this is the one
    /// genuine single-hop entry point that needs the fallback (see `safeReturnTo`'s doc comment for
    /// why every other handler doesn't).
    private func newBookmarkReturnContext(_ req: Request) -> (url: String, param: String) {
        let candidate = req.query[String.self, at: "returnTo"] ?? refererFallback(req)
        let url = validReturnTo(candidate)
        return (url, TagPresenter.queryValue(url))
    }

    /// A same-origin path+query parsed from the `Referer` header, or `nil` if there is none or it
    /// doesn't share this request's `Host`.
    private func refererFallback(_ req: Request) -> String? {
        guard let referer = req.headers.first(name: "Referer"),
              let components = URLComponents(string: referer),
              let refererHost = components.host,
              isSameHost(refererHost, as: req)
        else {
            return nil
        }

        return components.query.map { "\(components.path)?\($0)" } ?? components.path
    }

    /// Whether `host` (from a parsed `Referer`) matches the current request's own `Host` header,
    /// ignoring port — `Referer` is otherwise just a client-supplied string with no origin guarantee.
    /// Parses the `Host` header the same way as the `Referer` itself (via `URLComponents`) rather than
    /// a separate ad hoc port-strip, so both sides of the comparison handle ports/IPv6 identically.
    private func isSameHost(_ host: String, as req: Request) -> Bool {
        guard let hostHeader = req.headers.first(name: .host),
              let requestHost = URLComponents(string: "http://\(hostHeader)")?.host
        else {
            return false
        }

        return requestHost.caseInsensitiveCompare(host) == .orderedSame
    }

    /// Redirects back to a bookmark's detail page, re-attaching the `returnTo` context (if any) so
    /// the "← Back to bookmarks" link keeps pointing at the originating tag/Smart View list across
    /// detail-page actions (edit, archive, favicon refresh, Wayback submission). `safeReturnTo` here
    /// never falls back to `Referer` (see its `allowRefererFallback` parameter) — the detail page's
    /// own actions always carry either an explicit `returnTo` or none, so there's no self-referential
    /// risk from the Referer being the detail page's own prior URL.
    private func detailRedirect(
        _ req: Request,
        id: some CustomStringConvertible,
        ok: String? = nil,
        error: String? = nil
    ) -> Response {
        var components = URLComponents()
        components.path = "/app/bookmarks/\(id)"
        var items: [URLQueryItem] = []
        if let ok {
            items.append(.init(name: "ok", value: ok))
        }
        if let error {
            items.append(.init(name: "error", value: error))
        }
        let returnTo = safeReturnTo(req)
        if returnTo != "/app" {
            items.append(.init(name: "returnTo", value: returnTo))
        }
        components.queryItems = items.isEmpty ? nil : items
        return req.redirect(to: components.string ?? "/app/bookmarks/\(id)")
    }
}
