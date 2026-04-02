import Fluent
import Vapor

/// Server-rendered, user-facing web frontend (PRD §5, P2). Session-cookie auth (the
/// `stash_session` cookie), mounted at `/app`, entirely separate from the JSON `/api/v1/*`
/// endpoints and the `/admin` dashboard. All data access is scoped to the logged-in user.
struct AppWebController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        // Public — login / logout.
        routes.get("login", use: loginPage)
        routes.post("login", use: login)
        routes.post("logout", use: logout)

        // Everything else requires an authenticated (active) user session.
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

        app.get("tags", use: tagBrowser)

        app.get("settings", use: settings)
        app.post("settings", "password", use: changePassword)
        app.get("settings", "totp", use: totpSetup)
        app.post("settings", "totp", "verify", use: totpVerify)
        app.post("settings", "totp", "disable", use: totpDisable)
    }

    // MARK: - Login / logout

    // GET /app/login
    func loginPage(req: Request) async throws -> View {
        try await req.view.render("app-login", LoginPageContext(title: "Sign in", error: nil))
    }

    // POST /app/login
    func login(req: Request) async throws -> Response {
        let form = try req.content.decode(LoginForm.self)
        let username = form.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        func failure() async throws -> Response {
            try await render(
                req, "app-login",
                LoginPageContext(title: "Sign in", error: "Invalid username, password, or 2FA code."),
                status: .unauthorized
            )
        }

        guard let user = try await User.query(on: req.db).filter(\.$username == username).first() else {
            _ = try? await req.password.async.verify(form.password, created: Self.dummyHash)
            return try await failure()
        }
        // Any role may sign in here; suspended accounts are rejected.
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

    // POST /app/logout
    func logout(req: Request) async throws -> Response {
        req.session.destroy()
        return req.redirect(to: "/app/login")
    }

    // MARK: - Bookmark list

    // GET /app
    func list(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let query = try req.query.decode(BookmarkListQuery.self)

        let page = max(query.page ?? 1, 1)
        let per = 20
        let archived = query.archived ?? false

        let builder = try Bookmark.query(on: req.db)
            .filter(\.$user.$id == user.requireID())
            .filter(\.$isArchived == archived)

        if let term = query.q?.nonEmpty {
            builder.group(.or) { group in
                group.filter(\.$url ~~ term)
                group.filter(\.$title ~~ term)
                group.filter(\.$description ~~ term)
            }
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

        let total = result.metadata.total
        let pageCount = total == 0 ? 1 : (total + per - 1) / per

        return try await req.view.render("app-bookmarks", AppBookmarksContext(
            title: archived ? "Archived" : "Bookmarks",
            appUsername: user.username,
            bookmarks: try result.items.map { try Self.row(from: $0) },
            q: query.q?.nonEmpty ?? "",
            tag: query.tag?.nonEmpty ?? "",
            tagDisplay: Self.display(query.tag?.nonEmpty ?? ""),
            archived: archived,
            total: total,
            page: page,
            pageCount: pageCount,
            prevURL: page > 1 ? Self.listURL(query, page: page - 1) : nil,
            nextURL: page < pageCount ? Self.listURL(query, page: page + 1) : nil
        ))
    }

    // MARK: - Create

    // GET /app/bookmarks/new
    func newBookmarkForm(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        return try await req.view.render("app-bookmark-new", AppNewBookmarkContext(
            title: "Add bookmark", appUsername: user.username, error: nil, existingID: nil,
            url: "", bookmarkTitle: "", description: "", tags: "", previewed: false,
            knownTagsJSON: try await knownTagsJSON(req, user: user)
        ))
    }

    // POST /app/bookmarks  (action = "preview" | "save")
    func createBookmark(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let form = try req.content.decode(CreateBookmarkForm.self)

        let rawURL = form.url.trimmingCharacters(in: .whitespacesAndNewlines)
        var title = form.title?.nonEmpty
        var description = form.description?.nonEmpty
        let tagsText = form.tags ?? ""
        let tagsJSON = try await knownTagsJSON(req, user: user)

        func renderForm(error: String?, existingID: String? = nil, status: HTTPResponseStatus = .ok, previewed: Bool = false) async throws -> Response {
            try await render(req, "app-bookmark-new", AppNewBookmarkContext(
                title: "Add bookmark", appUsername: user.username, error: error, existingID: existingID,
                url: rawURL, bookmarkTitle: title ?? "", description: description ?? "",
                tags: tagsText, previewed: previewed, knownTagsJSON: tagsJSON
            ), status: status)
        }

        // Validate URL up front for both preview and save.
        let url: String
        do {
            url = try Bookmark.validatedURL(rawURL)
        } catch {
            return try await renderForm(error: "Enter a valid http(s) URL.", status: .unprocessableEntity)
        }

        // Preview: fetch metadata and pre-fill any blank fields, but don't save.
        if form.action == "preview" {
            let fetched = await MetadataFetcher.fetch(url: url, on: req)
            title = title ?? fetched.title
            description = description ?? fetched.description
            return try await renderForm(error: nil, previewed: true)
        }

        // Save.
        let userID = try user.requireID()
        if let existing = try await existingBookmark(url: url, userID: userID, on: req.db) {
            return try await renderForm(
                error: "You've already saved this URL.",
                existingID: try existing.requireID().uuidString,
                status: .conflict
            )
        }

        var faviconURL: String?
        if title == nil || description == nil {
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
            tags: Bookmark.normalizeTags(Self.parseTags(tagsText)),
            isArchived: false
        )
        do {
            try await bookmark.save(on: req.db)
        } catch {
            if let existing = try await existingBookmark(url: url, userID: userID, on: req.db) {
                return try await renderForm(
                    error: "You've already saved this URL.",
                    existingID: try existing.requireID().uuidString,
                    status: .conflict
                )
            }
            throw error
        }

        user.bookmarkCount += 1
        try await user.save(on: req.db)
        return req.redirect(to: "/app/bookmarks/\(try bookmark.requireID())?ok=created")
    }

    // MARK: - Detail / edit / update

    // GET /app/bookmarks/:id
    func bookmarkDetail(req: Request) async throws -> Response {
        guard let bookmark = try await loadBookmark(req) else { return req.redirect(to: "/app") }
        let message = Self.message(for: req.query[String.self, at: "ok"])
        return try await render(req, "app-bookmark-detail", AppBookmarkDetailContext(
            title: bookmark.title,
            appUsername: try req.auth.require(User.self).username,
            bookmark: try Self.row(from: bookmark),
            message: message
        ))
    }

    // GET /app/bookmarks/:id/edit
    func editBookmarkForm(req: Request) async throws -> Response {
        guard let bookmark = try await loadBookmark(req) else { return req.redirect(to: "/app") }
        return try await renderEdit(req, bookmark: bookmark, error: nil)
    }

    // POST /app/bookmarks/:id
    func updateBookmark(req: Request) async throws -> Response {
        guard let bookmark = try await loadBookmark(req) else { return req.redirect(to: "/app") }
        let form = try req.content.decode(EditBookmarkForm.self)

        bookmark.title = form.title?.nonEmpty ?? bookmark.url
        bookmark.description = form.description?.nonEmpty
        bookmark.applyTags(Bookmark.normalizeTags(Self.parseTags(form.tags ?? "")))
        bookmark.isArchived = form.archived != nil

        try await bookmark.save(on: req.db)
        return req.redirect(to: "/app/bookmarks/\(try bookmark.requireID())?ok=saved")
    }

    // POST /app/bookmarks/:id/delete
    func deleteBookmark(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        guard let bookmark = try await loadBookmark(req) else { return req.redirect(to: "/app") }
        try await bookmark.delete(on: req.db)
        user.bookmarkCount = max(user.bookmarkCount - 1, 0)
        try await user.save(on: req.db)
        return req.redirect(to: "/app")
    }

    // POST /app/bookmarks/:id/archive
    func archiveBookmark(req: Request) async throws -> Response {
        try await setArchived(req, true)
    }

    // POST /app/bookmarks/:id/unarchive
    func unarchiveBookmark(req: Request) async throws -> Response {
        try await setArchived(req, false)
    }

    private func setArchived(_ req: Request, _ archived: Bool) async throws -> Response {
        guard let bookmark = try await loadBookmark(req) else { return req.redirect(to: "/app") }
        bookmark.isArchived = archived
        try await bookmark.save(on: req.db)
        return req.redirect(to: "/app/bookmarks/\(try bookmark.requireID())?ok=\(archived ? "archived" : "unarchived")")
    }

    // MARK: - Tags

    // GET /app/tags
    func tagBrowser(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let bookmarks = try await Bookmark.query(on: req.db)
            .filter(\.$user.$id == user.requireID())
            .all()

        var counts: [String: Int] = [:]
        for bookmark in bookmarks {
            for tag in bookmark.tags { counts[tag, default: 0] += 1 }
        }
        let tags = counts
            .map { AppTagCount(name: $0.key, display: Self.display($0.key), count: $0.value) }
            .sorted { $0.name < $1.name }

        return try await req.view.render("app-tags", AppTagsContext(
            title: "Tags", appUsername: user.username, tags: tags
        ))
    }

    // MARK: - Settings & 2FA

    // GET /app/settings
    func settings(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        return try await req.view.render("app-settings", AppSettingsContext(
            title: "Settings", appUsername: user.username, isTOTPEnabled: user.isTOTPEnabled,
            error: nil, message: Self.message(for: req.query[String.self, at: "ok"])
        ))
    }

    // POST /app/settings/password
    func changePassword(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let form = try req.content.decode(AppChangePasswordForm.self)

        func settingsError(_ message: String) async throws -> Response {
            try await render(req, "app-settings", AppSettingsContext(
                title: "Settings", appUsername: user.username, isTOTPEnabled: user.isTOTPEnabled,
                error: message, message: nil
            ), status: .badRequest)
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

    // GET /app/settings/totp
    func totpSetup(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        if user.isTOTPEnabled {
            return req.redirect(to: "/app/settings")
        }
        // Generate (or regenerate, until confirmed) a secret and persist it.
        let secret = TOTP.generateSecret()
        user.totpSecret = secret
        try await user.save(on: req.db)

        return try await render(req, "app-totp-setup", AppTOTPSetupContext(
            title: "Enable 2FA", appUsername: user.username,
            secret: secret, otpauthURI: TOTP.otpauthURI(secret: secret, username: user.username),
            error: nil
        ))
    }

    // POST /app/settings/totp/verify
    func totpVerify(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let form = try req.content.decode(AppVerifyTOTPForm.self)

        guard let secret = user.totpSecret, let secretData = Base32.decode(secret) else {
            return req.redirect(to: "/app/settings/totp")
        }
        guard TOTP(secret: secretData).validate(form.totpCode) else {
            return try await render(req, "app-totp-setup", AppTOTPSetupContext(
                title: "Enable 2FA", appUsername: user.username,
                secret: secret, otpauthURI: TOTP.otpauthURI(secret: secret, username: user.username),
                error: "That code didn't match. Try again."
            ), status: .badRequest)
        }

        // Replace any prior recovery codes, then enable 2FA (mirrors the API).
        try await user.$recoveryCodes.query(on: req.db).delete()
        let plainCodes = RecoveryCodes.generate()
        for code in plainCodes {
            let hash = try await req.password.async.hash(RecoveryCodes.normalize(code))
            try await RecoveryCode(userID: user.requireID(), codeHash: hash).save(on: req.db)
        }
        user.isTOTPEnabled = true
        try await user.save(on: req.db)

        return try await render(req, "app-recovery-codes", AppRecoveryCodesContext(
            title: "Save your recovery codes", appUsername: user.username, codes: plainCodes
        ))
    }

    // POST /app/settings/totp/disable — confirm with a current TOTP code, then turn 2FA off.
    func totpDisable(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let form = try req.content.decode(AppDisableTOTPForm.self)

        // Nothing to disable.
        guard user.isTOTPEnabled, let secret = user.totpSecret, let secretData = Base32.decode(secret) else {
            return req.redirect(to: "/app/settings")
        }
        // Require a valid code so the user proves they still control the authenticator.
        guard TOTP(secret: secretData).validate(form.totpCode) else {
            return try await render(req, "app-settings", AppSettingsContext(
                title: "Settings", appUsername: user.username, isTOTPEnabled: user.isTOTPEnabled,
                error: "That code didn't match. Two-factor authentication was not disabled.", message: nil
            ), status: .badRequest)
        }

        try await user.$recoveryCodes.query(on: req.db).delete()
        user.totpSecret = nil
        user.isTOTPEnabled = false
        try await user.save(on: req.db)
        return req.redirect(to: "/app/settings?ok=totp_disabled")
    }

    // MARK: - Helpers

    /// Load a bookmark by id, scoped to the current user (cross-user access yields nil → 404/redirect).
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

    /// The distinct tag names the user has used, sorted — backs the create/edit autocomplete
    /// (same source as `GET /app/tags`).
    private func knownTagsJSON(_ req: Request, user: User) async throws -> String {
        let bookmarks = try await Bookmark.query(on: req.db)
            .filter(\.$user.$id == user.requireID())
            .all()
        var names = Set<String>()
        for bookmark in bookmarks { names.formUnion(bookmark.tags) }
        return Self.jsonArray(names.sorted())
    }

    static func jsonArray(_ strings: [String]) -> String {
        guard let data = try? JSONEncoder().encode(strings),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    private func renderEdit(_ req: Request, bookmark: Bookmark, error: String?) async throws -> Response {
        let user = try req.auth.require(User.self)
        return try await render(req, "app-bookmark-edit", AppEditBookmarkContext(
            title: "Edit",
            appUsername: user.username,
            error: error,
            id: try bookmark.requireID().uuidString,
            url: bookmark.url,
            bookmarkTitle: bookmark.title,
            description: bookmark.description ?? "",
            tags: bookmark.tags.joined(separator: ", "),
            isArchived: bookmark.isArchived,
            knownTagsJSON: try await knownTagsJSON(req, user: user)
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

    // MARK: - Pure helpers

    static func row(from bookmark: Bookmark) throws -> AppBookmarkRow {
        try AppBookmarkRow(
            id: bookmark.requireID().uuidString,
            url: bookmark.url,
            title: bookmark.title,
            description: bookmark.description,
            faviconURL: bookmark.faviconURL,
            tags: bookmark.tags.map { TagLink(name: $0, display: display($0)) },
            isArchived: bookmark.isArchived,
            createdAt: dateFormatter.string(from: bookmark.createdAt ?? Date())
        )
    }

    /// `swift/vapor` → `swift › vapor` for display.
    static func display(_ tag: String) -> String {
        tag.components(separatedBy: "/").joined(separator: " › ")
    }

    /// Split a free-text tag field on commas and whitespace.
    static func parseTags(_ raw: String) -> [String] {
        raw.components(separatedBy: CharacterSet(charactersIn: ",").union(.whitespacesAndNewlines))
    }

    /// Build a `/app` list URL preserving the active filters for a given page.
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
        case "created": return "Bookmark saved."
        case "saved": return "Changes saved."
        case "archived": return "Bookmark archived."
        case "unarchived": return "Bookmark unarchived."
        case "password": return "Password changed."
        case "totp_disabled": return "Two-factor authentication disabled."
        default: return nil
        }
    }

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// A valid bcrypt hash used to equalise timing for unknown usernames.
    static let dummyHash = "$2b$12$C6UzMDM.H6dfI/f/IKcEeO2x0jXJ8nKqK8h0V2vQ1nC3l6mFqKQ4u"
}
