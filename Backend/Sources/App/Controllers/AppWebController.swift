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

/// Server-rendered, user-facing web frontend (PRD §5, P2). Session-cookie auth (the
/// `stash_session` cookie), mounted at `/app`, entirely separate from the JSON `/api/v1/*`
/// endpoints and the `/admin` dashboard. All data access is scoped to the logged-in user.
struct AppWebController: RouteCollection {

    // MARK: Static Properties

    static let untaggedSentinel = Bookmark.untaggedSentinel

    static let todaySentinel = Bookmark.todaySentinel

    static let thisWeekSentinel = Bookmark.thisWeekSentinel

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static let dummyHash = "$2b$12$C6UzMDM.H6dfI/f/IKcEeO2x0jXJ8nKqK8h0V2vQ1nC3l6mFqKQ4u"

    // MARK: Static Computed Properties

    static var defaultField: SmartViewConditionField {
        SmartViewConditionField(
            type: "tag",
            textValue: "",
            boolValue: "true",
            isBool: false,
            isText: true,
            isDate: false
        )
    }

    // MARK: Static Functions

    static func buildSidebar(counts: [String: Int], activeTag: String) -> [SidebarTag] {
        var slugs = Set<String>()
        for key in counts.keys {
            let parts = key.split(separator: "/").map(String.init)
            guard !parts.isEmpty else { continue }

            for depth in 1...parts.count {
                slugs.insert(parts[0..<depth].joined(separator: "/"))
            }
        }
        let ordered = slugs.sorted { lhs, rhs in
            let a = lhs.split(separator: "/").map(String.init)
            let b = rhs.split(separator: "/").map(String.init)
            for i in 0..<min(a.count, b.count) where a[i] != b[i] {
                return a[i] < b[i]
            }
            return a.count < b.count
        }
        return ordered.map { slug in
            let comps = slug.split(separator: "/").map(String.init)
            return SidebarTag(
                label: comps.last ?? slug,
                href: tagHref(slug),
                count: counts[slug] ?? 0,
                depth: comps.count - 1,
                isActive: slug == activeTag
            )
        }
    }

    static func tagHref(_ slug: String) -> String {
        "/app?tag=\(queryValue(slug))"
    }

    static func queryValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "/?&=#+%")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    static func currentTheme(_ req: Request) -> String {
        switch req.cookies["stash_theme"]?.string {
        case "light": "light"
        case "dark": "dark"
        default: "auto"
        }
    }

    static func jsonArray(_ strings: [String]) -> String {
        guard let data = try? JSONEncoder().encode(strings),
              let json = String(data: data, encoding: .utf8) else { return "[]" }

        return json
    }

    // MARK: - Pure helpers

    static func row(from bookmark: Bookmark) throws -> AppBookmarkRow {
        try AppBookmarkRow(
            id: bookmark.requireID().uuidString,
            url: bookmark.url,
            title: bookmark.title,
            description: bookmark.description,
            faviconDomain: DomainExtractor.domain(from: bookmark.url),
            tags: bookmark.tags.map { TagLink(name: $0, display: display($0)) },
            isArchived: bookmark.isArchived,
            createdAt: dateFormatter.string(from: bookmark.createdAt ?? Date())
        )
    }

    static func display(_ tag: String) -> String {
        tag.components(separatedBy: "/").joined(separator: " › ")
    }

    static func parseTags(_ raw: String) -> [String] {
        raw.components(separatedBy: CharacterSet(charactersIn: ",").union(.whitespacesAndNewlines))
    }

    static func smartViewListURL(id: String, archived: Bool, page: Int) -> String {
        var components = URLComponents()
        components.path = "/app/smart-views/\(id)"
        var items: [URLQueryItem] = []
        if archived { items.append(.init(name: "archived", value: "true")) }

        if page > 1 { items.append(.init(name: "page", value: String(page))) }

        components.queryItems = items.isEmpty ? nil : items
        return components.string ?? "/app/smart-views/\(id)"
    }

    static func summary(for conditions: [SmartViewCondition], matchMode: String) -> String {
        let prefix = matchMode == SmartView.matchAny ? "Match any" : "Match all"
        let labels = conditions.map { conditionLabel($0) }.joined(separator: ", ")

        return "\(prefix): \(labels)"
    }

    static func conditionLabel(_ condition: SmartViewCondition) -> String {
        switch condition {
        case let .tag(value): "Tag: \(value)"
        case let .urlContains(value): "URL contains “\(value)”"
        case let .titleContains(value): "Title contains “\(value)”"
        case let .descriptionContains(value): "Description contains “\(value)”"
        case let .createdBefore(date): "Created before \(SmartViewCondition.iso8601.string(from: date).prefix(10))"
        case let .createdAfter(date): "Created after \(SmartViewCondition.iso8601.string(from: date).prefix(10))"
        case let .isArchived(value): "Archived: \(value ? "Yes" : "No")"
        case let .hasTags(value): "Has tags: \(value ? "Yes" : "No")"
        }
    }

    static func normalizedConditionValue(type: String, value: String) -> String {
        guard type == "createdBefore" || type == "createdAfter" else { return value }

        if value.count == 10, value.contains("-"), !value.contains("T") {
            return value + "T00:00:00Z"
        }

        return value
    }

    static func conditions(from form: SmartViewForm) throws -> [SmartViewCondition] {
        let types = form.conditionType ?? []
        let values = form.conditionValue ?? []
        var result: [SmartViewCondition] = []
        for (index, type) in types.enumerated() {
            let raw = (index < values.count ? values[index] : "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }

            try result.append(SmartViewCondition.validated(
                type: type,
                value: normalizedConditionValue(type: type, value: raw)
            ))
        }
        guard !result.isEmpty else {
            throw APIError.validationFailed("Add at least one condition with a value.")
        }

        return result
    }

    static func fields(from form: SmartViewForm) -> [SmartViewConditionField] {
        let types = form.conditionType ?? []
        let values = form.conditionValue ?? []
        var fields: [SmartViewConditionField] = []
        for (index, type) in types.enumerated() {
            let value = index < values.count ? values[index] : ""
            fields.append(field(type: type, rawValue: value))
        }
        return fields.isEmpty ? [defaultField] : fields
    }

    static func field(from condition: SmartViewCondition) -> SmartViewConditionField {
        let type = condition.typeString
        var raw = condition.valueString
        if type == "createdBefore" || type == "createdAfter" {
            raw = String(raw.prefix(10))
        }

        return field(type: type, rawValue: raw)
    }

    static func field(type: String, rawValue: String) -> SmartViewConditionField {
        let isBool = type == "isArchived" || type == "hasTags"
        let isDate = type == "createdBefore" || type == "createdAfter"
        let boolValue = (isBool && rawValue.lowercased() == "false") ? "false" : "true"

        return SmartViewConditionField(
            type: type,
            textValue: isBool ? "" : rawValue,
            boolValue: boolValue,
            isBool: isBool,
            isText: !isBool,
            isDate: isDate
        )
    }

    static func listURL(_ query: BookmarkListQuery, page: Int) -> String {
        var components = URLComponents()
        components.path = "/app"
        var items: [URLQueryItem] = []
        if let q = query.q?.nonEmpty { items.append(.init(name: "q", value: q)) }
        if let tag = query.tag?.nonEmpty { items.append(.init(name: "tag", value: tag)) }
        if query.archived == true { items.append(.init(name: "archived", value: "true")) }
        if page > 1 { items.append(.init(name: "page", value: String(page))) }
        components.queryItems = items.isEmpty ? nil : items
        return components.string ?? "/app"
    }

    static func message(for ok: String?) -> String? {
        switch ok {
        case "created": "Bookmark saved."
        case "saved": "Changes saved."
        case "archived": "Bookmark archived."
        case "unarchived": "Bookmark unarchived."
        case "password": "Password changed."
        case "totp_disabled": "Two-factor authentication disabled."
        case "theme": "Appearance updated."
        case "favicon_refreshing": "Favicon refresh started — it may take a moment to update."
        default: nil
        }
    }

    static func notice(for value: String?) -> String? {
        switch value {
        case "all_bookmarks_deleted": "All your bookmarks were deleted."
        default: nil
        }
    }

    // MARK: Functions

    func boot(routes: RoutesBuilder) throws {
        routes.get("login", use: loginPage)
        routes.post("login", use: login)
        routes.post("logout", use: logout)

        let app = routes.grouped(UserSessionMiddleware())
        app.get(use: list)

        let bookmarks = app.grouped("bookmarks")
        bookmarks.get("new", use: newBookmarkForm)
        bookmarks.post(use: createBookmark)
        bookmarks.get(":bookmarkID", use: bookmarkDetail)
        bookmarks.get(":bookmarkID", "edit", use: editBookmarkForm)
        bookmarks.post(":bookmarkID", use: updateBookmark)
        bookmarks.post(":bookmarkID", "delete", use: deleteBookmark)
        bookmarks.post(":bookmarkID", "archive", use: archiveBookmark)
        bookmarks.post(":bookmarkID", "unarchive", use: unarchiveBookmark)
        bookmarks.post(":bookmarkID", "refresh-favicon", use: refreshFavicon)

        let smartViews = app.grouped("smart-views")
        smartViews.get(use: smartViewManage)
        smartViews.get("new", use: newSmartViewForm)
        smartViews.post("new", use: createSmartView)
        smartViews.get(":smartViewID", use: smartViewResults)
        smartViews.get(":smartViewID", "edit", use: editSmartViewForm)
        smartViews.post(":smartViewID", "edit", use: updateSmartView)
        smartViews.post(":smartViewID", "delete", use: deleteSmartView)

        app.get("tags", use: tagBrowser)
        app.post("tags", "rename", use: renameTag)
        app.post("tags", "delete", use: deleteTag)

        app.get("settings", use: settings)
        app.post("settings", "password", use: changePassword)
        app.get("settings", "totp", use: totpSetup)
        app.post("settings", "totp", "verify", use: totpVerify)
        app.post("settings", "totp", "disable", use: totpDisable)
        app.post("settings", "delete-all-bookmarks", use: deleteAllBookmarks)
        app.post("settings", "theme", use: setTheme)

        app.on(.POST, "import", body: .collect(maxSize: "16mb"), use: importBookmarks)
        app.get("export", use: exportBookmarks)
    }

    // MARK: - Login / logout

    func loginPage(req: Request) async throws -> View {
        try await req.view.render("app-login", LoginPageContext(title: "Sign in", error: nil, chrome: req.siteChrome()))
    }

    func login(req: Request) async throws -> Response {
        let form = try req.content.decode(LoginForm.self)
        let username = form.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        func failure() async throws -> Response {
            try await render(
                req, "app-login",
                LoginPageContext(
                    title: "Sign in",
                    error: "Invalid username, password, or 2FA code.",
                    chrome: req.siteChrome()
                ),
                status: .unauthorized
            )
        }

        guard let user = try await User.query(on: req.db).filter(\.$username == username).first() else {
            _ = try? await req.password.async.verify(form.password, created: Self.dummyHash)
            return try await failure()
        }
        guard try await req.password.async.verify(form.password, created: user.passwordHash),
              user.isActive
        else {
            return try await failure()
        }

        if user.isTOTPEnabled {
            guard let code = form.totpCode?.nonEmpty,
                  let secret = user.totpSecret,
                  let secretData = Base32.decode(secret),
                  TOTP(secret: secretData).validate(code)
            else {
                return try await failure()
            }
        }

        req.session.data[UserSessionMiddleware.sessionKey] = try user.requireID().uuidString
        return req.redirect(to: "/app")
    }

    func logout(req: Request) async throws -> Response {
        req.session.destroy()
        return req.redirect(to: "/app/login")
    }

    // MARK: - Bookmark list

    func list(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let query = try req.query.decode(BookmarkListQuery.self)

        let page = max(query.page ?? 1, 1)
        let per = 20
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
        let pageCount = total == 0 ? 1 : (total + per - 1) / per

        let rawTag = query.tag?.nonEmpty
        let isUntagged = rawTag == Self.untaggedSentinel
        let isToday = rawTag == Self.todaySentinel
        let isThisWeek = rawTag == Self.thisWeekSentinel
        let isSpecial = isUntagged || isToday || isThisWeek
        let activeTag = isSpecial ? "" : Bookmark.normalizeTagQuery(query.tag ?? "")
        let sidebar = try await sidebarTags(
            for: user,
            activeTag: activeTag,
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
                Self.display(rawTag ?? "")
            }

        let smartViews = try await sidebarSmartViews(for: user, activeID: "", on: req.db)

        return try await req.view.render("app-bookmarks", AppBookmarksContext(
            title: archived ? "Archived" : "Bookmarks",
            appUsername: user.username,
            appIsAdmin: user.role == .admin,
            bookmarks: result.items.map { try Self.row(from: $0) },
            q: query.q?.nonEmpty ?? "",
            tag: rawTag ?? "",
            tagDisplay: tagDisplay,
            archived: archived,
            total: total,
            page: page,
            pageCount: pageCount,
            prevURL: page > 1 ? Self.listURL(query, page: page - 1) : nil,
            nextURL: page < pageCount ? Self.listURL(query, page: page + 1) : nil,
            notice: Self.notice(for: req.query[String.self, at: "notice"]),
            sidebarTags: sidebar.tags,
            untaggedCount: sidebar.untaggedCount,
            untaggedActive: isUntagged,
            todayCount: sidebar.todayCount,
            todayActive: isToday,
            thisWeekCount: sidebar.thisWeekCount,
            thisWeekActive: isThisWeek,
            smartViews: smartViews,
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
            knownTagsJSON: knownTagsJSON(req, user: user),
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
        let tagsJSON = try await knownTagsJSON(req, user: user)

        func renderForm(
            error: String?,
            existingID: String? = nil,
            status: HTTPResponseStatus = .ok,
            previewed: Bool = false
        ) async throws -> Response {
            try await render(req, "app-bookmark-new", AppNewBookmarkContext(
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
            tags: Bookmark.normalizeTags(Self.parseTags(tagsText)),
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
        FaviconFetcher.enqueue(forURL: url, declaredIconURL: declaredIcon, on: req.application)

        return try req.redirect(to: "/app/bookmarks/\(bookmark.requireID())?ok=created")
    }

    // MARK: - Detail / edit / update

    func bookmarkDetail(req: Request) async throws -> Response {
        guard let bookmark = try await loadBookmark(req) else { return req.redirect(to: "/app") }

        let message = Self.message(for: req.query[String.self, at: "ok"])
        return try await render(req, "app-bookmark-detail", AppBookmarkDetailContext(
            title: bookmark.title,
            appUsername: req.auth.require(User.self).username,
            appIsAdmin: req.auth.require(User.self).role == .admin,
            bookmark: Self.row(from: bookmark),
            message: message,
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
        bookmark.applyTags(Bookmark.normalizeTags(Self.parseTags(form.tags ?? "")))
        bookmark.isArchived = form.archived != nil

        try await bookmark.save(on: req.db)
        return try req.redirect(to: "/app/bookmarks/\(bookmark.requireID())?ok=saved")
    }

    func deleteBookmark(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        guard let bookmark = try await loadBookmark(req) else { return req.redirect(to: "/app") }

        let bookmarkID = try bookmark.requireID()
        let userID = try user.requireID()

        try await bookmark.delete(on: req.db)
        try await DeletedBookmark.record(bookmarkID: bookmarkID, userID: userID, on: req.db)
        user.bookmarkCount = max(user.bookmarkCount - 1, 0)
        try await user.save(on: req.db)
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

    // MARK: - Smart Views

    func smartViewResults(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        guard let smartView = try await loadSmartView(req) else { return req.redirect(to: "/app/smart-views") }

        let id = try smartView.requireID().uuidString
        let overridesArchived = smartView.conditions.contains { if case .isArchived = $0 { true } else { false } }
        let archived = !overridesArchived && (req.query[Bool.self, at: "archived"] ?? false)
        let page = max(req.query[Int.self, at: "page"] ?? 1, 1)
        let per = 20
        let boundaries = Bookmark.dateBoundaries()

        let builder = try Bookmark.query(on: req.db)
            .filter(\.$user.$id == user.requireID())
        smartView.applyConditions(to: builder, archivedDefault: archived)

        let result = try await builder
            .sort(\.$createdAt, .descending)
            .sort(\.$id, .descending)
            .paginate(PageRequest(page: page, per: per))

        let total = result.metadata.total
        let pageCount = total == 0 ? 1 : (total + per - 1) / per
        let sidebar = try await sidebarTags(
            for: user,
            activeTag: "",
            today: boundaries.today,
            week: boundaries.week,
            on: req.db
        )
        let smartViews = try await sidebarSmartViews(for: user, activeID: id, on: req.db)

        return try await render(req, "app-bookmarks", AppBookmarksContext(
            title: smartView.name,
            appUsername: user.username,
            appIsAdmin: user.role == .admin,
            bookmarks: result.items.map { try Self.row(from: $0) },
            q: "",
            tag: "",
            tagDisplay: "",
            archived: archived,
            total: total,
            page: page,
            pageCount: pageCount,
            prevURL: page > 1 ? Self.smartViewListURL(id: id, archived: archived, page: page - 1) : nil,
            nextURL: page < pageCount ? Self.smartViewListURL(id: id, archived: archived, page: page + 1) : nil,
            notice: nil,
            sidebarTags: sidebar.tags,
            untaggedCount: sidebar.untaggedCount,
            untaggedActive: false,
            todayCount: sidebar.todayCount,
            todayActive: false,
            thisWeekCount: sidebar.thisWeekCount,
            thisWeekActive: false,
            smartViews: smartViews,
            isSmartView: true,
            smartViewID: id,
            showArchivedToggle: !overridesArchived,
            chrome: req.siteChrome()
        ))
    }

    func smartViewManage(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let smartViews = try await SmartView.query(on: req.db)
            .filter(\.$user.$id == user.requireID())
            .sort(\.$name)
            .all()
        let rows = try smartViews.map { view in
            try AppSmartViewRow(
                id: view.requireID().uuidString,
                name: view.name,
                summary: Self.summary(for: view.conditions, matchMode: view.matchMode)
            )
        }
        let message: String? = switch req.query[String.self, at: "ok"] {
        case "saved": "Smart View saved."
        case "deleted": "Smart View deleted."
        default: nil
        }

        return try await req.view.render("app-smart-views", AppSmartViewsContext(
            title: "Smart Views",
            appUsername: user.username,
            appIsAdmin: user.role == .admin,
            smartViews: rows,
            message: message,
            chrome: req.siteChrome()
        ))
    }

    func newSmartViewForm(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)

        return try await renderSmartViewForm(
            req, user,
            title: "New Smart View",
            isEdit: false,
            action: "/app/smart-views/new",
            name: "",
            matchMode: SmartView.matchAll,
            conditions: [Self.defaultField],
            error: nil
        )
    }

    func createSmartView(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let form = try req.content.decode(SmartViewForm.self)

        do {
            let name = try SmartViewController.validatedName(form.name)
            let matchMode = try SmartViewController.validatedMatchMode(form.matchMode)
            let conditions = try Self.conditions(from: form)
            let smartView = try SmartView(
                userID: user.requireID(),
                name: name,
                conditions: conditions,
                matchMode: matchMode
            )
            try await smartView.save(on: req.db)

            return req.redirect(to: "/app/smart-views?ok=saved")
        } catch let error as APIError {
            return try await renderSmartViewForm(
                req, user,
                title: "New Smart View",
                isEdit: false,
                action: "/app/smart-views/new",
                name: form.name,
                matchMode: form.matchMode ?? SmartView.matchAll,
                conditions: Self.fields(from: form),
                error: error.reason,
                status: .unprocessableEntity
            )
        }
    }

    func editSmartViewForm(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        guard let smartView = try await loadSmartView(req) else { return req.redirect(to: "/app/smart-views") }

        let id = try smartView.requireID().uuidString
        return try await renderSmartViewForm(
            req, user,
            title: "Edit Smart View",
            isEdit: true,
            action: "/app/smart-views/\(id)/edit",
            name: smartView.name,
            matchMode: smartView.matchMode,
            conditions: smartView.conditions.map { Self.field(from: $0) },
            error: nil
        )
    }

    func updateSmartView(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        guard let smartView = try await loadSmartView(req) else { return req.redirect(to: "/app/smart-views") }

        let id = try smartView.requireID().uuidString
        let form = try req.content.decode(SmartViewForm.self)

        do {
            smartView.name = try SmartViewController.validatedName(form.name)
            smartView.matchMode = try SmartViewController.validatedMatchMode(form.matchMode)
            smartView.conditions = try Self.conditions(from: form)
            try await smartView.save(on: req.db)

            return req.redirect(to: "/app/smart-views?ok=saved")
        } catch let error as APIError {
            return try await renderSmartViewForm(
                req, user,
                title: "Edit Smart View",
                isEdit: true,
                action: "/app/smart-views/\(id)/edit",
                name: form.name,
                matchMode: form.matchMode ?? SmartView.matchAll,
                conditions: Self.fields(from: form),
                error: error.reason,
                status: .unprocessableEntity
            )
        }
    }

    func deleteSmartView(req: Request) async throws -> Response {
        guard let smartView = try await loadSmartView(req) else { return req.redirect(to: "/app/smart-views") }

        try await smartView.delete(on: req.db)
        return req.redirect(to: "/app/smart-views?ok=deleted")
    }

    // MARK: - Tags

    func tagBrowser(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let bookmarks = try await Bookmark.query(on: req.db)
            .filter(\.$user.$id == user.requireID())
            .all()

        var counts: [String: Int] = [:]
        for bookmark in bookmarks {
            for tag in bookmark.tags {
                counts[tag, default: 0] += 1
            }
        }
        let tags = counts
            .map { AppTagCount(name: $0.key, display: Self.display($0.key), count: $0.value) }
            .sorted { $0.name < $1.name }

        var message: String?
        switch req.query[String.self, at: "ok"] {
        case "renamed":
            let from = req.query[String.self, at: "from"] ?? ""
            let to = req.query[String.self, at: "to"] ?? ""
            let count = req.query[Int.self, at: "n"] ?? 0
            message = "Renamed \(from) to \(to) (\(count) bookmark\(count == 1 ? "" : "s") updated)."
        case "deleted":
            let tag = req.query[String.self, at: "tag"] ?? ""
            let count = req.query[Int.self, at: "n"] ?? 0
            message = "Deleted \(tag) (\(count) bookmark\(count == 1 ? "" : "s") updated)."
        default:
            message = nil
        }
        let error: String? = switch req.query[String.self, at: "error"] {
        case "rename": "Couldn't rename the tag — both names must be non-empty."
        case "delete": "Couldn't delete the tag — it must be a non-empty tag name."
        default: nil
        }

        return try await req.view.render("app-tags", AppTagsContext(
            title: "Tags", appUsername: user.username, appIsAdmin: user.role == .admin, tags: tags, message: message,
            error: error,
            chrome: req.siteChrome()
        ))
    }

    func renameTag(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let form = try req.content.decode(TagRenameForm.self)
        do {
            let result = try await TagRenamer.rename(
                rawFrom: form.from,
                rawTo: form.to,
                for: user.requireID(),
                on: req.db
            )
            let from = Self.queryValue(result.from)
            let to = Self.queryValue(result.to)
            return req.redirect(to: "/app/tags?ok=renamed&from=\(from)&to=\(to)&n=\(result.affectedBookmarks)")
        } catch is APIError {
            return req.redirect(to: "/app/tags?error=rename")
        }
    }

    func deleteTag(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let form = try req.content.decode(TagDeleteForm.self)
        do {
            let result = try await TagDeleter.delete(
                rawTag: form.tag,
                for: user.requireID(),
                on: req.db
            )
            let tag = Self.queryValue(result.tag)
            return req.redirect(to: "/app/tags?ok=deleted&tag=\(tag)&n=\(result.affectedBookmarks)")
        } catch is APIError {
            return req.redirect(to: "/app/tags?error=delete")
        }
    }

    // MARK: - Settings & 2FA

    func settings(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)

        var importSummary: ImportSummaryContext?
        if req.query[String.self, at: "imported"] == "1",
           let stored = req.session.data["importSummary"],
           let data = stored.data(using: .utf8)
        {
            importSummary = try? JSONDecoder().decode(ImportSummaryContext.self, from: data)
            req.session.data["importSummary"] = nil
        }

        return try await req.view.render("app-settings", settingsContext(
            req,
            user,
            message: Self.message(for: req.query[String.self, at: "ok"]),
            importSummary: importSummary
        ))
    }

    func changePassword(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let form = try req.content.decode(AppChangePasswordForm.self)

        func settingsError(_ message: String) async throws -> Response {
            try await render(req, "app-settings", settingsContext(req, user, error: message), status: .badRequest)
        }

        guard try await req.password.async.verify(form.currentPassword, created: user.passwordHash) else {
            return try await settingsError("Current password is incorrect.")
        }
        guard form.newPassword.count >= 12 else {
            return try await settingsError("New password must be at least 12 characters.")
        }

        user.passwordHash = try await req.password.async.hash(form.newPassword)
        try await user.save(on: req.db)
        return req.redirect(to: "/app/settings?ok=password")
    }

    func totpSetup(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        if user.isTOTPEnabled {
            return req.redirect(to: "/app/settings")
        }
        let secret = TOTP.generateSecret()
        user.totpSecret = secret
        try await user.save(on: req.db)

        return try await render(req, "app-totp-setup", AppTOTPSetupContext(
            title: "Enable 2FA", appUsername: user.username, appIsAdmin: user.role == .admin,
            secret: secret, otpauthURI: TOTP.otpauthURI(secret: secret, username: user.username),
            error: nil,
            chrome: req.siteChrome()
        ))
    }

    func totpVerify(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let form = try req.content.decode(AppVerifyTOTPForm.self)

        guard let secret = user.totpSecret, let secretData = Base32.decode(secret) else {
            return req.redirect(to: "/app/settings/totp")
        }
        guard TOTP(secret: secretData).validate(form.totpCode) else {
            return try await render(req, "app-totp-setup", AppTOTPSetupContext(
                title: "Enable 2FA", appUsername: user.username, appIsAdmin: user.role == .admin,
                secret: secret, otpauthURI: TOTP.otpauthURI(secret: secret, username: user.username),
                error: "That code didn't match. Try again.",
                chrome: req.siteChrome()
            ), status: .badRequest)
        }

        try await user.$recoveryCodes.query(on: req.db).delete()
        let plainCodes = RecoveryCodes.generate()
        for code in plainCodes {
            let hash = try await req.password.async.hash(RecoveryCodes.normalize(code))
            try await RecoveryCode(userID: user.requireID(), codeHash: hash).save(on: req.db)
        }
        user.isTOTPEnabled = true
        try await user.save(on: req.db)

        return try await render(req, "app-recovery-codes", AppRecoveryCodesContext(
            title: "Save your recovery codes", appUsername: user.username, appIsAdmin: user.role == .admin,
            codes: plainCodes,
            chrome: req.siteChrome()
        ))
    }

    func totpDisable(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let form = try req.content.decode(AppDisableTOTPForm.self)

        guard user.isTOTPEnabled, let secret = user.totpSecret, let secretData = Base32.decode(secret) else {
            return req.redirect(to: "/app/settings")
        }
        guard TOTP(secret: secretData).validate(form.totpCode) else {
            return try await render(req, "app-settings", settingsContext(
                req, user, error: "That code didn't match. Two-factor authentication was not disabled."
            ), status: .badRequest)
        }

        try await user.$recoveryCodes.query(on: req.db).delete()
        user.totpSecret = nil
        user.isTOTPEnabled = false
        try await user.save(on: req.db)
        return req.redirect(to: "/app/settings?ok=totp_disabled")
    }

    // MARK: - Import / export

    func importBookmarks(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let form = try req.content.decode(ImportForm.self)

        func importError(_ message: String) async throws -> Response {
            try await render(req, "app-settings", settingsContext(req, user, importError: message), status: .badRequest)
        }

        guard let importer = ImportExportRegistry.shared.importer(for: form.format) else {
            return try await importError("Unknown import format.")
        }

        let data = Data(buffer: form.file.data)
        guard !data.isEmpty else {
            return try await importError("Please choose a file to import.")
        }

        let result: ImportResult
        do {
            result = try await importer.import(from: data, for: user.requireID(), on: req.db)
        } catch let error as ImportError {
            return try await importError(error.description)
        }

        try FaviconFetcher.enqueueBackfill(forUser: user.requireID(), on: req.application)

        if let data = try? JSONEncoder().encode(ImportSummaryContext(result)),
           let json = String(data: data, encoding: .utf8)
        {
            req.session.data["importSummary"] = json
        }
        return req.redirect(to: "/app/settings?imported=1")
    }

    func exportBookmarks(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let format = req.query[String.self, at: "format"] ?? StashJSONExporter.identifier
        guard let exporter = ImportExportRegistry.shared.exporter(for: format) else {
            return req.redirect(to: "/app/settings")
        }

        let data = try await exporter.export(for: user.requireID(), on: req.db)
        let filename = "stash-export-\(Self.fileDateFormatter.string(from: Date())).\(type(of: exporter).fileExtension)"

        let response = Response(status: .ok)
        response.headers.replaceOrAdd(name: .contentType, value: type(of: exporter).mimeType)
        response.headers.replaceOrAdd(name: .contentDisposition, value: "attachment; filename=\"\(filename)\"")
        response.body = .init(data: data)
        return response
    }

    // MARK: - Danger zone

    func deleteAllBookmarks(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let form = try req.content.decode(DeleteAllBookmarksForm.self)

        guard form.confirm.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "delete all" else {
            return try await render(req, "app-settings", settingsContext(
                req, user, error: "Type “delete all” to confirm — no bookmarks were deleted."
            ), status: .badRequest)
        }

        let userID = try user.requireID()
        let bookmarkIDs = try await user.$bookmarks.query(on: req.db).all().map { try $0.requireID() }

        try await user.$bookmarks.query(on: req.db).delete()
        for bookmarkID in bookmarkIDs {
            try await DeletedBookmark.record(bookmarkID: bookmarkID, userID: userID, on: req.db)
        }
        user.bookmarkCount = 0
        try await user.save(on: req.db)

        return req.redirect(to: "/app?notice=all_bookmarks_deleted")
    }

    // MARK: - Appearance

    func setTheme(req: Request) async throws -> Response {
        _ = try req.auth.require(User.self)
        let form = try req.content.decode(ThemeForm.self)
        let theme: String = switch form.theme {
        case "light", "dark", "auto": form.theme
        default: "auto"
        }

        let response = req.redirect(to: "/app/settings?ok=theme")
        response.cookies["stash_theme"] = HTTPCookies.Value(
            string: theme,
            expires: Date(timeIntervalSinceNow: 60 * 60 * 24 * 365),
            maxAge: 60 * 60 * 24 * 365,
            domain: nil,
            path: "/",
            isSecure: false,
            isHTTPOnly: false,
            sameSite: .lax
        )
        return response
    }

    private func sidebarTags(
        for user: User,
        activeTag: String,
        today: Date,
        week: Date,
        on db: any Database
    ) async throws -> (tags: [SidebarTag], untaggedCount: Int, todayCount: Int, thisWeekCount: Int) {
        let bookmarks = try await Bookmark.query(on: db)
            .filter(\.$user.$id == user.requireID())
            .all()
        var counts: [String: Int] = [:]
        var untaggedCount = 0
        var todayCount = 0
        var thisWeekCount = 0
        for bookmark in bookmarks {
            if bookmark.tags.isEmpty { untaggedCount += 1 }

            if let created = bookmark.createdAt {
                if created >= today { todayCount += 1 }

                if created >= week { thisWeekCount += 1 }
            }

            for tag in bookmark.tags {
                counts[tag, default: 0] += 1
            }
        }
        return (Self.buildSidebar(counts: counts, activeTag: activeTag), untaggedCount, todayCount, thisWeekCount)
    }

    private func setArchived(_ req: Request, _ archived: Bool) async throws -> Response {
        guard let bookmark = try await loadBookmark(req) else { return req.redirect(to: "/app") }

        bookmark.isArchived = archived
        try await bookmark.save(on: req.db)
        return try req.redirect(to: "/app/bookmarks/\(bookmark.requireID())?ok=\(archived ? "archived" : "unarchived")")
    }

    private func settingsContext(
        _ req: Request,
        _ user: User,
        error: String? = nil,
        message: String? = nil,
        importError: String? = nil,
        importSummary: ImportSummaryContext? = nil
    ) -> AppSettingsContext {
        AppSettingsContext(
            title: "Settings",
            appUsername: user.username,
            appIsAdmin: user.role == .admin,
            isTOTPEnabled: user.isTOTPEnabled,
            error: error,
            message: message,
            importers: ImportExportRegistry.shared.importerOptions,
            exporters: ImportExportRegistry.shared.exporterOptions,
            importError: importError,
            importSummary: importSummary,
            theme: Self.currentTheme(req),
            chrome: req.siteChrome()
        )
    }

    // MARK: - Helpers

    private func loadSmartView(_ req: Request) async throws -> SmartView? {
        let user = try req.auth.require(User.self)
        guard let id = req.parameters.get("smartViewID", as: UUID.self) else { return nil }

        return try await SmartView.query(on: req.db)
            .filter(\.$user.$id == user.requireID())
            .filter(\.$id == id)
            .first()
    }

    private func sidebarSmartViews(
        for user: User,
        activeID: String,
        on db: any Database
    ) async throws -> [SidebarSmartView] {
        let views = try await SmartView.query(on: db)
            .filter(\.$user.$id == user.requireID())
            .sort(\.$name)
            .all()
        return try views.map { view in
            let id = try view.requireID().uuidString
            return SidebarSmartView(name: view.name, href: "/app/smart-views/\(id)", isActive: id == activeID)
        }
    }

    private func renderSmartViewForm(
        _ req: Request,
        _ user: User,
        title: String,
        isEdit: Bool,
        action: String,
        name: String,
        matchMode: String,
        conditions: [SmartViewConditionField],
        error: String?,
        status: HTTPResponseStatus = .ok
    ) async throws -> Response {
        try await render(req, "app-smart-view-form", AppSmartViewFormContext(
            title: title,
            appUsername: user.username,
            appIsAdmin: user.role == .admin,
            error: error,
            isEdit: isEdit,
            action: action,
            name: name,
            matchMode: matchMode,
            conditions: conditions,
            knownTagsJSON: knownTagsJSON(req, user: user),
            chrome: req.siteChrome()
        ), status: status)
    }

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

    private func knownTagsJSON(_ req: Request, user: User) async throws -> String {
        let bookmarks = try await Bookmark.query(on: req.db)
            .filter(\.$user.$id == user.requireID())
            .all()
        var names = Set<String>()
        for bookmark in bookmarks {
            names.formUnion(bookmark.tags)
        }
        return Self.jsonArray(names.sorted())
    }

    private func renderEdit(_ req: Request, bookmark: Bookmark, error: String?) async throws -> Response {
        let user = try req.auth.require(User.self)
        return try await render(req, "app-bookmark-edit", AppEditBookmarkContext(
            title: "Edit",
            appUsername: user.username,
            appIsAdmin: user.role == .admin,
            error: error,
            id: bookmark.requireID().uuidString,
            url: bookmark.url,
            bookmarkTitle: bookmark.title,
            description: bookmark.description ?? "",
            tags: bookmark.tags.joined(separator: ", "),
            isArchived: bookmark.isArchived,
            knownTagsJSON: knownTagsJSON(req, user: user),
            chrome: req.siteChrome()
        ))
    }

    private func render(
        _ req: Request,
        _ template: String,
        _ context: some Encodable,
        status: HTTPResponseStatus = .ok
    ) async throws -> Response {
        let view: View = try await req.view.render(template, context)
        let response = Response(status: status)
        response.headers.contentType = .html
        response.body = .init(buffer: view.data)
        return response
    }
}
