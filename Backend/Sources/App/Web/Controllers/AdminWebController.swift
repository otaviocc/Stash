// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Logging
import SQLKit
import Vapor

// MARK: - AdminWebController

/// Server-rendered web admin dashboard (PRD §11). Session-cookie auth, mounted at `/admin`,
/// entirely separate from the JSON `/api/v1/*` endpoints. Enforces the same business rules as
/// the admin API: accounts are always created as `user`, self-deletion is blocked, and a
/// password reset (or suspension) invalidates the target's refresh tokens.
struct AdminWebController: RouteCollection {

    // MARK: Static Functions

    /// Formats the drain worker's current phase into a short admin-facing sentence. `internal`, not
    /// `private`, so it's directly unit-testable without needing a live worker/database.
    static func queueStatusText(enabled: Bool, pendingCount: Int, state: WaybackWorker.QueueState) -> String {
        guard enabled else { return "Disabled — no submissions will run." }

        switch state {
        case .idle:
            return pendingCount > 0
                ? "Paused — \(pendingCount) bookmark\(pendingCount == 1 ? "" : "s") queued, waiting to start."
                : "Idle — nothing queued."
        case let .submitting(url):
            return "Submitting now: \(url)"
        case .waitingNormalPace:
            return "Running — next submission in about 30 seconds."
        case let .waitingAfterRateLimit(url, attempt, maxAttempts):
            return "Rate-limited — retrying \(url) in about 5 minutes (attempt \(attempt + 1) of \(maxAttempts))."
        }
    }

    // MARK: Functions

    func boot(routes: RoutesBuilder) throws {
        routes.get("login", use: loginPage)
        routes.post("login", use: login)
        routes.post("logout", use: logout)

        let protected = routes.grouped(AdminSessionMiddleware())
        protected.get(use: dashboard)
        protected.get("users", use: userList)
        protected.get("users", "new", use: newUserForm)
        protected.post("users", "new", use: createUser)
        protected.get("users", ":userID", use: userDetail)
        protected.post("users", ":userID", "suspend", use: suspend)
        protected.post("users", ":userID", "unsuspend", use: unsuspend)
        protected.post("users", ":userID", "reset-password", use: resetPassword)
        protected.post("users", ":userID", "reset-totp", use: resetTOTP)
        protected.post("users", ":userID", "delete", use: deleteUser)
        protected.get("appearance", use: appearance)
        protected.post("appearance", use: saveAppearance)
        protected.get("audit", use: auditLog)
        protected.get("sessions", use: sessionsPage)
        protected.post("sessions", "revoke-all", use: revokeAllSessionsPage)
        protected.post("sessions", "revoke-user", use: revokeUserSessionsPage)
        protected.get("health", use: health)
        protected.post("health", "check-updates", use: checkUpdates)
        protected.post("health", "toggle-updates", use: toggleUpdateCheck)
        protected.get("backup", use: backup)
        protected.get("backup", "download", use: downloadBackup)
        protected.on(.POST, "backup", "restore", body: .collect(maxSize: "16mb"), use: restoreBackup)
        protected.get("maintenance", use: maintenance)
        protected.post("db", "optimize", use: optimizeDatabase)
        protected.get("favicons", use: favicons)
        protected.post("favicons", "clear", use: clearFavicons)
        protected.post("favicons", "rescan", use: rescanFavicons)
        protected.get("internet-archive", use: internetArchive)
        protected.post("internet-archive", "toggle", use: toggleInternetArchive)
        protected.post("internet-archive", "retry-failed", use: retryFailedInternetArchive)
        protected.post("internet-archive", "queue-all", use: queueAllInternetArchive)
        protected.post("internet-archive", "resume", use: resumeInternetArchive)
        protected.get("logs", use: logsPage)
    }

    // MARK: - Login / logout

    func loginPage(req: Request) async throws -> View {
        try await req.view.render("login", LoginPageContext(title: "Sign in", error: nil, chrome: req.siteChrome()))
    }

    func login(req: Request) async throws -> Response {
        let form = try req.content.decode(LoginForm.self)
        let username = form.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        func failure() async throws -> Response {
            await AuditLogger.record(
                action: "login_failure",
                actor: username,
                detail: "admin dashboard login",
                ip: AuditLogger.clientIP(from: req),
                on: req.db
            )
            return try await req.renderHTML(
                "login",
                LoginPageContext(
                    title: "Sign in",
                    error: "Invalid username, password, or 2FA code.",
                    chrome: req.siteChrome()
                ),
                status: .unauthorized
            )
        }

        guard let user = try await User.query(on: req.db).filter(\.$username == username).first() else {
            _ = try? await req.password.async.verify(form.password, created: User.dummyPasswordHash)
            return try await failure()
        }
        guard try await req.password.async.verify(form.password, created: user.passwordHash),
              user.isActive,
              user.role == .admin
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

        await AuditLogger.record(
            action: "login_success",
            actor: user.username,
            detail: "admin dashboard login",
            ip: AuditLogger.clientIP(from: req),
            on: req.db
        )
        req.session.data[AdminSessionMiddleware.sessionKey] = try user.requireID().uuidString
        return req.redirect(to: "/admin")
    }

    func logout(req: Request) async throws -> Response {
        let actor = try await SessionUsernameResolver.resolve(
            fromSessionKey: AdminSessionMiddleware.sessionKey, req: req
        )
        req.session.destroy()
        await AuditLogger.record(
            action: "logout",
            actor: actor,
            detail: "admin dashboard logout",
            ip: AuditLogger.clientIP(from: req),
            on: req.db
        )

        return req.redirect(to: "/admin/login")
    }

    // MARK: - Dashboard

    func dashboard(req: Request) async throws -> View {
        let admin = try req.auth.require(User.self)

        UpdateChecker.refreshIfStale(on: req.application)

        async let users = User.query(on: req.db).sort(\.$username).all()
        async let sessionRows = ActiveSessionLoader.loadActiveSessions(on: req)
        async let archiveQueuedCount = Bookmark.query(on: req.db).filter(\.$waybackStatus == .pending).count()
        async let cachedFaviconCount = FaviconCache.query(on: req.db).filter(\.$status == .cached).count()
        async let pendingFaviconCount = FaviconCache.query(on: req.db).filter(\.$status == .pending).count()
        async let recentAuditEntries = AuditLog.query(on: req.db)
            .sort(\.$createdAt, .descending)
            .limit(8)
            .all()

        let (
            userList, sessions, archiveQueued, cachedFavicons, pendingFavicons, auditEntries
        ) = try await (
            users,
            sessionRows,
            archiveQueuedCount,
            cachedFaviconCount,
            pendingFaviconCount,
            recentAuditEntries
        )

        let rows = try userList.map { try $0.asRow() }
        let totalBookmarks = rows.reduce(0) { $0 + $1.bookmarkCount }
        let activeUsers = rows.filter(\.isActive).count

        let archiveEnabled = WaybackSubmitter.isInstanceEnabled(on: req.application)
        let archiveDetail = archiveEnabled ? "\(archiveQueued) queued" : "Disabled"

        let recentActivity = auditEntries.map { entry in
            AuditLogRowContext(
                time: DateFormatter.webDateTime.string(from: entry.createdAt ?? Date()),
                actor: entry.actorUsername ?? "(unknown)",
                action: entry.action,
                detail: entry.detail ?? "—"
            )
        }

        let cards = [
            DashboardCardContext(
                title: "Users",
                href: "/admin/users",
                description: "Manage accounts, suspend, reset passwords or 2FA.",
                detail: "\(rows.count) users · \(rows.count - activeUsers) suspended"
            ),
            DashboardCardContext(
                title: "New user",
                href: "/admin/users/new",
                description: "Create a new account.",
                detail: nil
            ),
            DashboardCardContext(
                title: "Appearance",
                href: "/admin/appearance",
                description: "Accent theme, about message, footer link.",
                detail: nil
            ),
            DashboardCardContext(
                title: "Audit log",
                href: "/admin/audit",
                description: "Auth events and admin actions, most recent first.",
                detail: nil
            ),
            DashboardCardContext(
                title: "Sessions",
                href: "/admin/sessions",
                description: "Every live web session, admin and app.",
                detail: "\(sessions.count) live"
            ),
            DashboardCardContext(
                title: "Health",
                href: "/admin/health",
                description: "Version, database, uptime, disk usage.",
                detail: nil
            ),
            DashboardCardContext(
                title: "Maintenance",
                href: "/admin/maintenance",
                description: "Run a database optimize (VACUUM).",
                detail: nil
            ),
            DashboardCardContext(
                title: "Favicons",
                href: "/admin/favicons",
                description: "Cached site icons; clear or re-scan.",
                detail: "\(cachedFavicons) cached · \(pendingFavicons) pending"
            ),
            DashboardCardContext(
                title: "Internet Archive",
                href: "/admin/internet-archive",
                description: "Wayback Machine submission queue and settings.",
                detail: archiveDetail
            ),
            DashboardCardContext(
                title: "Logs",
                href: "/admin/logs",
                description: "Recent server log lines.",
                detail: nil
            ),
            DashboardCardContext(
                title: "Backup & Restore",
                href: "/admin/backup",
                description: "Download or restore a full instance backup.",
                detail: nil
            )
        ]

        let updateStatus = req.application.storage[UpdateStatusCacheKey.self]?.current
        let updateBanner = updateStatus?.updateAvailable == true
            ? "An update is available: \(updateStatus?.latestVersion ?? "?") (currently running \(updateStatus?.currentVersion ?? "?"))."
            : nil

        return try await req.view.render("dashboard", DashboardContext(
            title: "Dashboard",
            adminUsername: admin.username,
            totalUsers: rows.count,
            activeUsers: activeUsers,
            suspendedUsers: rows.count - activeUsers,
            totalBookmarks: totalBookmarks,
            liveSessions: sessions.count,
            archiveQueued: archiveQueued,
            updateBanner: updateBanner,
            updateReleaseURL: updateStatus?.releaseURL,
            cards: cards,
            recentActivity: recentActivity,
            chrome: req.siteChrome()
        ))
    }

    // MARK: - Health

    func health(req: Request) async throws -> Response {
        UpdateChecker.refreshIfStale(on: req.application)

        let message = FlashMessage.admin(for: req.query[String.self, at: "ok"])
        let error = FlashMessage.adminError(for: req.query[String.self, at: "error"])
        return try await renderHealth(req, message: message, error: error)
    }

    /// Forces an immediate update check (the "Check now" button), ignoring the normal 24h
    /// staleness window — still a no-op if the admin has disabled update checking or a check is
    /// already in flight, in which case the flash reflects that nothing actually ran rather than
    /// always claiming success.
    func checkUpdates(req: Request) async throws -> Response {
        let didRun = await UpdateChecker.forceCheck(on: req.application)
        let flash = didRun ? "update_checked" : "update_check_skipped"
        return req.redirect(to: "/admin/health?ok=\(flash)")
    }

    func toggleUpdateCheck(req: Request) async throws -> Response {
        let admin = try req.auth.require(User.self)
        let form = try req.content.decode(UpdateCheckToggleForm.self)
        let settings = try await SiteSettingsService.current(on: req.db)
        settings.updateCheckEnabled = form.enabled ?? false
        try await settings.save(on: req.db)
        SiteSettingsService.refreshCache(with: settings, on: req.application)

        await AuditLogger.record(
            action: "update_check_toggled",
            actor: admin.username,
            detail: "update_check_enabled set to \(settings.updateCheckEnabled)",
            ip: AuditLogger.clientIP(from: req),
            on: req.db
        )

        return req
            .redirect(to: "/admin/health?ok=\(settings.updateCheckEnabled ? "updates_enabled" : "updates_disabled")")
    }

    // MARK: - User list & create

    func userList(req: Request) async throws -> View {
        let admin = try req.auth.require(User.self)
        let users = try await User.query(on: req.db).sort(\.$username).all()
        return try await req.view.render("users", UsersContext(
            title: "Users",
            adminUsername: admin.username,
            users: users.map { try $0.asRow() },
            chrome: req.siteChrome()
        ))
    }

    func newUserForm(req: Request) async throws -> View {
        let admin = try req.auth.require(User.self)
        return try await req.view.render("user-new", NewUserContext(
            title: "New user", adminUsername: admin.username, error: nil, username: nil,
            chrome: req.siteChrome()
        ))
    }

    func createUser(req: Request) async throws -> Response {
        let admin = try req.auth.require(User.self)
        let form = try req.content.decode(CreateUserForm.self)
        let username = form.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        func formError(_ message: String) async throws -> Response {
            try await req.renderHTML(
                "user-new",
                NewUserContext(
                    title: "New user", adminUsername: admin.username, error: message, username: username,
                    chrome: req.siteChrome()
                ),
                status: .badRequest
            )
        }

        guard !username.isEmpty else { return try await formError("Username must not be empty.") }
        guard form.password.count >= 12 else {
            return try await formError("Password must be at least 12 characters.")
        }

        if try await User.query(on: req.db).filter(\.$username == username).first() != nil {
            return try await formError("That username is already taken.")
        }

        let user = try await User(
            username: username,
            passwordHash: req.password.async.hash(form.password),
            role: .user
        )
        do {
            try await user.save(on: req.db)
        } catch {
            return try await formError("That username is already taken.")
        }

        await AuditLogger.record(
            action: "user_created",
            actor: admin.username,
            detail: "created user \(username)",
            ip: AuditLogger.clientIP(from: req),
            on: req.db
        )

        return try req.redirect(to: "/admin/users/\(user.requireID())?ok=created")
    }

    // MARK: - User detail & actions

    func userDetail(req: Request) async throws -> Response {
        guard let user = try await loadUser(req) else {
            return req.redirect(to: "/admin/users")
        }

        let message = FlashMessage.admin(for: req.query[String.self, at: "ok"])
        return try await renderDetail(req, user: user, error: nil, message: message)
    }

    func suspend(req: Request) async throws -> Response {
        let admin = try req.auth.require(User.self)
        guard let user = try await loadUser(req) else { return req.redirect(to: "/admin/users") }

        if try user.requireID() == admin.requireID() {
            return try await renderDetail(
                req, user: user, error: "You cannot suspend your own account.", message: nil,
                status: .badRequest
            )
        }

        let wasActive = user.isActive
        user.isActive = false
        try await user.save(on: req.db)
        try await user.$refreshTokens.query(on: req.db).delete()
        await AuditLogger.record(
            if: wasActive,
            action: "user_suspended",
            actor: admin.username,
            detail: "suspended \(user.username)",
            ip: AuditLogger.clientIP(from: req),
            on: req.db
        )

        return try req.redirect(to: "/admin/users/\(user.requireID())?ok=suspended")
    }

    func unsuspend(req: Request) async throws -> Response {
        let admin = try req.auth.require(User.self)
        guard let user = try await loadUser(req) else { return req.redirect(to: "/admin/users") }

        let wasActive = user.isActive
        user.isActive = true
        try await user.save(on: req.db)
        await AuditLogger.record(
            if: !wasActive,
            action: "user_unsuspended",
            actor: admin.username,
            detail: "unsuspended \(user.username)",
            ip: AuditLogger.clientIP(from: req),
            on: req.db
        )

        return try req.redirect(to: "/admin/users/\(user.requireID())?ok=unsuspended")
    }

    func resetPassword(req: Request) async throws -> Response {
        let admin = try req.auth.require(User.self)
        guard let user = try await loadUser(req) else { return req.redirect(to: "/admin/users") }

        let form = try req.content.decode(ResetPasswordForm.self)

        guard form.password.count >= 12 else {
            return try await renderDetail(
                req, user: user, error: "Password must be at least 12 characters.", message: nil,
                status: .badRequest
            )
        }

        user.passwordHash = try await req.password.async.hash(form.password)
        try await user.save(on: req.db)
        try await user.$refreshTokens.query(on: req.db).delete()
        await AuditLogger.record(
            action: "password_reset",
            actor: admin.username,
            detail: "reset password for \(user.username)",
            ip: AuditLogger.clientIP(from: req),
            on: req.db
        )

        return try req.redirect(to: "/admin/users/\(user.requireID())?ok=password-reset")
    }

    func resetTOTP(req: Request) async throws -> Response {
        let admin = try req.auth.require(User.self)
        guard let user = try await loadUser(req) else { return req.redirect(to: "/admin/users") }
        guard user.hasTOTPConfigured else {
            return try req.redirect(to: "/admin/users/\(user.requireID())?ok=totp_reset")
        }

        try await user.disableTOTP(on: req.db)

        await AuditLogger.record(
            action: "totp_reset",
            actor: admin.username,
            detail: "reset 2FA for \(user.username)",
            ip: AuditLogger.clientIP(from: req),
            on: req.db
        )

        return try req.redirect(to: "/admin/users/\(user.requireID())?ok=totp_reset")
    }

    func deleteUser(req: Request) async throws -> Response {
        let admin = try req.auth.require(User.self)
        guard let user = try await loadUser(req) else { return req.redirect(to: "/admin/users") }

        if try user.requireID() == admin.requireID() {
            return try await renderDetail(
                req, user: user, error: "You cannot delete your own account.", message: nil,
                status: .badRequest
            )
        }

        let deletedUsername = user.username

        try await user.$bookmarks.query(on: req.db).delete()
        try await user.$refreshTokens.query(on: req.db).delete()
        try await user.$recoveryCodes.query(on: req.db).delete()
        try await user.delete(on: req.db)

        await AuditLogger.record(
            action: "user_deleted",
            actor: admin.username,
            detail: "deleted user \(deletedUsername)",
            ip: AuditLogger.clientIP(from: req),
            on: req.db
        )

        return req.redirect(to: "/admin/users")
    }

    // MARK: - Appearance

    func appearance(req: Request) async throws -> Response {
        let admin = try req.auth.require(User.self)
        let settings = try await SiteSettingsService.current(on: req.db)
        let message = req.query[String.self, at: "ok"] == "saved" ? "Appearance saved." : nil

        return try await renderAppearance(
            req,
            admin: admin,
            accentTheme: settings.accentTheme,
            aboutText: settings.aboutText ?? "",
            footerLinks: settings.footerLinks,
            error: nil,
            message: message
        )
    }

    func saveAppearance(req: Request) async throws -> Response {
        let admin = try req.auth.require(User.self)
        let form = try req.content.decode(AppearanceForm.self)

        let accentTheme = form.accentTheme.trimmingCharacters(in: .whitespacesAndNewlines)
        let aboutText = form.aboutText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        func trim(_ s: String?) -> String {
            s?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        let links: [FooterLink] = [
            .init(label: trim(form.footerLink0Label), url: trim(form.footerLink0URL)),
            .init(label: trim(form.footerLink1Label), url: trim(form.footerLink1URL)),
            .init(label: trim(form.footerLink2Label), url: trim(form.footerLink2URL)),
            .init(label: trim(form.footerLink3Label), url: trim(form.footerLink3URL))
        ]

        func formError(_ message: String) async throws -> Response {
            try await renderAppearance(
                req,
                admin: admin,
                accentTheme: accentTheme,
                aboutText: aboutText,
                footerLinks: links,
                error: message,
                message: nil,
                status: .unprocessableEntity
            )
        }

        guard AccentTheme.validIdentifiers.contains(accentTheme) else {
            return try await formError("Choose one of the available accent themes.")
        }
        guard aboutText.count <= 280 else {
            return try await formError("The about message must be 280 characters or fewer.")
        }

        for link in links where !link.url.isEmpty {
            guard link.url.lowercased().hasPrefix("https://") else {
                return try await formError("All footer link URLs must start with https://.")
            }
        }

        let settings = try await SiteSettingsService.current(on: req.db)

        let oldTheme = settings.accentTheme
        let oldAbout = settings.aboutText ?? ""
        let oldLinks = settings.footerLinks

        settings.accentTheme = accentTheme
        settings.aboutText = aboutText.isEmpty ? nil : aboutText
        settings.footerLinks = links
        try await settings.save(on: req.db)
        SiteSettingsService.refreshCache(with: settings, on: req.application)

        var changed: [String] = []
        if accentTheme != oldTheme { changed.append("accent theme: \(accentTheme)") }
        if aboutText != oldAbout { changed.append("about text") }
        if links != oldLinks { changed.append("footer links") }

        await AuditLogger.record(
            action: "appearance_updated",
            actor: admin.username,
            detail: changed.isEmpty ? "no changes" : changed.joined(separator: ", "),
            ip: AuditLogger.clientIP(from: req),
            on: req.db
        )

        return req.redirect(to: "/admin/appearance?ok=saved")
    }

    // MARK: - Audit log

    func auditLog(req: Request) async throws -> View {
        let admin = try req.auth.require(User.self)
        let entries = try await AuditLog.query(on: req.db)
            .sort(\.$createdAt, .descending)
            .limit(50)
            .all()

        let rows = entries.map { entry in
            AuditLogRowContext(
                time: DateFormatter.webDateTime.string(from: entry.createdAt ?? Date()),
                actor: entry.actorUsername ?? "(unknown)",
                action: entry.action,
                detail: entry.detail ?? "—"
            )
        }

        return try await req.view.render("audit", AuditLogContext(
            title: "Audit log",
            adminUsername: admin.username,
            entries: rows,
            chrome: req.siteChrome()
        ))
    }

    // MARK: - Sessions

    func sessionsPage(req: Request) async throws -> Response {
        let message = FlashMessage.admin(for: req.query[String.self, at: "ok"])
        return try await renderSessions(req, message: message, error: nil)
    }

    func revokeAllSessionsPage(req: Request) async throws -> Response {
        let admin = try req.auth.require(User.self)

        _ = ActiveSessionLoader.revokeAll(on: req.application)
        try await RefreshToken.query(on: req.db).delete()

        await AuditLogger.record(
            action: "sessions_revoked_all",
            actor: admin.username,
            detail: "revoked all active sessions",
            ip: AuditLogger.clientIP(from: req),
            on: req.db
        )

        // The current request's own session was cached before the store was cleared above,
        // and SessionsMiddleware writes that cached copy back to the store when the response
        // is sent — destroying it here (rather than leaving it to naturally expire) makes
        // "revoke all" actually include the admin's own session, matching the flash copy.
        req.session.destroy()
        return req.redirect(to: "/admin/sessions?ok=sessions-revoked-all")
    }

    func revokeUserSessionsPage(req: Request) async throws -> Response {
        let admin = try req.auth.require(User.self)
        let form = try req.content.decode(RevokeUserSessionsForm.self)
        let username = form.userName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard let user = try await User.query(on: req.db).filter(\.$username == username).first() else {
            return try await renderSessions(
                req, message: nil, error: "No user named \"\(username)\" was found.",
                status: .badRequest
            )
        }

        let targetID = try user.requireID()
        ActiveSessionLoader.revokeForUser(userID: targetID, on: req.application)
        try await user.$refreshTokens.query(on: req.db).delete()

        await AuditLogger.record(
            action: "sessions_revoked_user",
            actor: admin.username,
            detail: "revoked sessions for \(user.username)",
            ip: AuditLogger.clientIP(from: req),
            on: req.db
        )

        // Same self-revocation subtlety as revokeAllSessionsPage: if the admin targeted their
        // own account, destroy the current request's cached session too, or SessionsMiddleware
        // will write it straight back into the store when the response is sent.
        if targetID == (try? admin.requireID()) {
            req.session.destroy()
        }
        return req.redirect(to: "/admin/sessions?ok=sessions-revoked-user")
    }

    // MARK: - Maintenance

    func maintenance(req: Request) async throws -> Response {
        let admin = try req.auth.require(User.self)
        let ok = req.query[String.self, at: "ok"]
        let elapsedMS = req.query[Int.self, at: "ms"]

        var message = FlashMessage.admin(for: ok)
        if ok == "db_optimized", let elapsedMS {
            let seconds = Double(elapsedMS) / 1000.0
            message = "Database optimize complete (\(String(format: "%.1f", seconds))s)."
        }

        let error = FlashMessage.adminError(for: req.query[String.self, at: "error"])

        let context = MaintenanceContext(
            title: "Maintenance",
            adminUsername: admin.username,
            message: message,
            error: error,
            chrome: req.siteChrome()
        )
        return try await req.renderHTML("maintenance", context, status: error == nil ? .ok : .badRequest)
    }

    func optimizeDatabase(req: Request) async throws -> Response {
        guard let sql = req.db as? SQLDatabase else {
            return req.redirect(to: "/admin/maintenance?error=unsupported_driver")
        }

        let start = Date()
        do {
            try await sql.raw("VACUUM").run()
        } catch {
            req.logger.error("Database optimize failed: \(String(reflecting: error))")
            return req.redirect(to: "/admin/maintenance?error=vacuum_failed")
        }
        let elapsedMS = Int(Date().timeIntervalSince(start) * 1000)

        return req.redirect(to: "/admin/maintenance?ok=db_optimized&ms=\(elapsedMS)")
    }

    // MARK: - Favicons

    func favicons(req: Request) async throws -> Response {
        let admin = try req.auth.require(User.self)
        let message = FlashMessage.admin(for: req.query[String.self, at: "ok"])
        return try await renderFavicons(req, admin: admin, message: message)
    }

    func clearFavicons(req: Request) async throws -> Response {
        try await FaviconCache.query(on: req.db).delete()
        return req.redirect(to: "/admin/favicons?ok=favicons_cleared")
    }

    func rescanFavicons(req: Request) async throws -> Response {
        _ = try await FaviconFetcher.refreshAll(on: req.application)
        return req.redirect(to: "/admin/favicons?ok=favicons_rescanning")
    }

    // MARK: - Internet Archive

    func internetArchive(req: Request) async throws -> Response {
        let admin = try req.auth.require(User.self)
        let message = FlashMessage.admin(for: req.query[String.self, at: "ok"])
        let error = FlashMessage.adminError(for: req.query[String.self, at: "error"])
        return try await renderInternetArchive(req, admin: admin, message: message, error: error)
    }

    func toggleInternetArchive(req: Request) async throws -> Response {
        let admin = try req.auth.require(User.self)
        let form = try req.content.decode(InternetArchiveToggleForm.self)
        let settings = try await SiteSettingsService.current(on: req.db)
        settings.internetArchiveEnabled = form.enabled ?? false
        try await settings.save(on: req.db)
        SiteSettingsService.refreshCache(with: settings, on: req.application)

        await AuditLogger.record(
            action: "internet_archive_toggled",
            actor: admin.username,
            detail: "internet_archive_enabled set to \(settings.internetArchiveEnabled)",
            ip: AuditLogger.clientIP(from: req),
            on: req.db
        )

        return req.redirect(to: "/admin/internet-archive?ok=ia_saved")
    }

    func retryFailedInternetArchive(req: Request) async throws -> Response {
        try await requeueInternetArchive(matching: [.failed], flashKey: "ia_retrying", req: req)
    }

    func queueAllInternetArchive(req: Request) async throws -> Response {
        try await requeueInternetArchive(matching: [.none, .failed], flashKey: "ia_queued", req: req)
    }

    /// Manually nudges the drain worker — a safe no-op if it's already draining (`kick()` is
    /// idempotent), useful if the queue ever looks paused/stuck without an obvious trigger to resume
    /// it (a new bookmark, a bulk action, or a restart).
    func resumeInternetArchive(req: Request) async throws -> Response {
        guard WaybackSubmitter.isInstanceEnabled(on: req.application) else {
            return req.redirect(to: "/admin/internet-archive?error=internet_archive_disabled")
        }

        WaybackSubmitter.kick(on: req.application)
        return req.redirect(to: "/admin/internet-archive?ok=ia_resumed")
    }

    // MARK: - Logs

    func logsPage(req: Request) async throws -> View {
        let admin = try req.auth.require(User.self)

        // The dropdown in logs.leaf only offers these three; anything else (a hand-crafted
        // ?level=critical, say) is treated as no filter, so the rendered selection never
        // silently diverges from what's actually being filtered.
        let selectableLevels: Set<Logger.Level> = [.info, .warning, .error]
        let rawLevel = req.query[String.self, at: "level"]?.nonEmpty
        let selectedLevel = rawLevel
            .flatMap { Logger.Level(rawValue: $0) }
            .flatMap { selectableLevels.contains($0) ? $0 : nil }
        let selectedLevelString = selectedLevel?.rawValue

        let entries = sharedLogBuffer.snapshot(level: selectedLevel).map { entry in
            LogEntryRow(
                timestamp: DateFormatter.webDateTime.string(from: entry.timestamp),
                level: entry.level.rawValue,
                label: entry.label,
                message: entry.message
            )
        }

        return try await req.view.render("logs", LogsContext(
            title: "Logs",
            adminUsername: admin.username,
            entries: entries,
            selectedLevel: selectedLevelString,
            chrome: req.siteChrome()
        ))
    }

    // MARK: - Backup & Restore

    func backup(req: Request) async throws -> Response {
        let message = FlashMessage.admin(for: req.query[String.self, at: "ok"])
        let error = FlashMessage.adminError(for: req.query[String.self, at: "error"])
        return try await renderBackup(req, message: message, error: error)
    }

    /// Streams a full instance backup (every account's auth material, bookmarks, and Smart Views,
    /// plus site settings) as a downloadable JSON file. See `InstanceBackupService` for exactly
    /// what's included and why the file is sensitive.
    func downloadBackup(req: Request) async throws -> Response {
        let data = try await InstanceBackupService.export(on: req.db)
        let filename = "stash-instance-backup-\(DateFormatter.webFileDate.string(from: Date())).json"

        let response = Response(status: .ok)
        response.headers.replaceOrAdd(name: .contentType, value: "application/json")
        response.headers.replaceOrAdd(name: .contentDisposition, value: "attachment; filename=\"\(filename)\"")
        response.body = .init(data: data)
        return response
    }

    func restoreBackup(req: Request) async throws -> Response {
        let admin = try req.auth.require(User.self)
        let form = try req.content.decode(RestoreBackupForm.self)

        guard form.confirm.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "restore" else {
            return try await renderBackup(
                req, message: nil, error: FlashMessage.adminError(for: "restore_confirm"), status: .badRequest
            )
        }

        let data = Data(buffer: form.file.data)
        guard !data.isEmpty else {
            return try await renderBackup(
                req, message: nil, error: FlashMessage.adminError(for: "restore_file_missing"), status: .badRequest
            )
        }

        let result: RestoreResult
        do {
            result = try await InstanceBackupService.restore(from: data, on: req.application)
        } catch is InstanceBackupError {
            return try await renderBackup(
                req, message: nil, error: FlashMessage.adminError(for: "restore_invalid"), status: .badRequest
            )
        }

        await AuditLogger.record(
            action: "backup_restored",
            actor: admin.username,
            detail: "\(result.usersCreated) created, \(result.usersMerged) merged, "
                + "\(result.bookmarksImported) bookmarks imported, \(result.bookmarksUpdated) updated, "
                + "\(result.smartViewsImported) Smart Views imported, \(result.smartViewsUpdated) updated"
                + (result.skipped.isEmpty ? "" : ", \(result.skipped.count) records skipped"),
            ip: AuditLogger.clientIP(from: req),
            on: req.db
        )

        return req.redirect(to: "/admin/backup?ok=backup_restored")
    }

    /// Shared by both bulk actions: re-queues every bookmark whose `waybackStatus` matches one of
    /// `statuses` and wakes the drain worker. Refuses (PRG `?error=internet_archive_disabled`) when
    /// the admin has turned Internet Archive submissions off instance-wide, so a bulk action can
    /// never bypass the same switch every other submission path already respects.
    private func requeueInternetArchive(
        matching statuses: [WaybackStatus],
        flashKey: String,
        req: Request
    ) async throws -> Response {
        guard WaybackSubmitter.isInstanceEnabled(on: req.application) else {
            return req.redirect(to: "/admin/internet-archive?error=internet_archive_disabled")
        }

        try await Bookmark.query(on: req.db)
            .filter(\.$waybackStatus ~~ statuses)
            .set(\.$waybackStatus, to: .pending)
            .update()
        WaybackSubmitter.kick(on: req.application)
        return req.redirect(to: "/admin/internet-archive?ok=\(flashKey)")
    }

    // MARK: - Health helpers

    /// Pings the database with a trivial `SELECT 1` to confirm connectivity, and reports which
    /// driver is active. Never throws — a failed connection is reported as an `"error"` status
    /// string rather than surfacing an exception to the page.
    private func checkDatabase(_ req: Request) async -> (statusText: String, isOK: Bool, driver: String) {
        let driver = req.application.environment == .testing ? "SQLite" : "Postgres"

        guard let sqlDB = req.db as? SQLDatabase else {
            return ("unknown", false, driver)
        }

        do {
            try await sqlDB.raw("SELECT 1").run()
            return ("ok", true, driver)
        } catch {
            req.logger.error("Health check DB probe failed: \(error)")
            return ("error", false, driver)
        }
    }

    /// Formats the elapsed time since process boot as `"Nd Nh Nm"`, omitting leading zero units
    /// (e.g. an app up for less than an hour shows just `"12m"`, not `"0d 0h 12m"`).
    private func formattedUptime(req: Request) -> String {
        guard let bootDate = req.application.storage[BootDateKey.self] else {
            return "unknown"
        }

        let seconds = max(0, Int(Date().timeIntervalSince(bootDate)))
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60

        var parts: [String] = []

        if days > 0 {
            parts.append("\(days)d")
        }

        if days > 0 || hours > 0 {
            parts.append("\(hours)h")
        }
        parts.append("\(minutes)m")

        return parts.joined(separator: " ")
    }

    /// Reads filesystem free/total space for the working directory. Returns `"unavailable"` on any
    /// failure rather than crashing the page — disk introspection is a nice-to-have, not essential.
    private func diskUsageSummary(req: Request) -> String {
        let path = req.application.directory.workingDirectory

        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: path),
              let totalSize = attributes[.systemSize] as? NSNumber,
              let freeSize = attributes[.systemFreeSize] as? NSNumber
        else {
            return "unavailable"
        }

        let total = totalSize.doubleValue
        let free = freeSize.doubleValue
        let used = total - free

        return "\(formattedBytes(used)) / \(formattedBytes(total))"
    }

    /// Formats a byte count as a human-readable `GB`/`MB`/`KB`/`B` string, one decimal place above
    /// the byte scale, picking the largest unit that reads as at least `1`.
    private func formattedBytes(_ bytes: Double) -> String {
        let gigabytes = bytes / 1_073_741_824

        if gigabytes >= 1 {
            return String(format: "%.1f GB", gigabytes)
        }

        let megabytes = bytes / 1_048_576

        if megabytes >= 1 {
            return String(format: "%.1f MB", megabytes)
        }

        let kilobytes = bytes / 1024

        if kilobytes >= 1 {
            return String(format: "%.1f KB", kilobytes)
        }

        return "\(Int(bytes)) B"
    }

    // MARK: - Helpers

    private func renderSessions(
        _ req: Request,
        message: String?,
        error: String?,
        status: HTTPResponseStatus = .ok
    ) async throws -> Response {
        let admin = try req.auth.require(User.self)
        let rows = try await ActiveSessionLoader.loadActiveSessions(on: req)
        let webRows = rows.map {
            SessionRowWebContext(
                id: $0.id,
                userID: $0.userID.uuidString,
                username: $0.username,
                sessionType: $0.sessionType == .admin ? "Admin Dashboard" : "Web UI",
                userIsActive: $0.userIsActive
            )
        }

        let context = SessionsContext(
            title: "Sessions",
            adminUsername: admin.username,
            sessions: webRows,
            total: webRows.count,
            message: message,
            error: error,
            chrome: req.siteChrome()
        )
        return try await req.renderHTML("sessions", context, status: status)
    }

    private func renderFavicons(
        _ req: Request,
        admin: User,
        message: String?,
        status: HTTPResponseStatus = .ok
    ) async throws -> Response {
        let rows = try await FaviconCache.query(on: req.db).all()

        var cachedCount = 0
        var pendingCount = 0
        var failedCount = 0
        var totalBytes = 0

        for row in rows {
            switch row.status {
            case .cached: cachedCount += 1
            case .pending: pendingCount += 1
            case .failed: failedCount += 1
            }
            totalBytes += row.imageData?.count ?? 0
        }

        let context = FaviconAdminContext(
            title: "Favicons",
            adminUsername: admin.username,
            totalCount: rows.count,
            cachedCount: cachedCount,
            pendingCount: pendingCount,
            failedCount: failedCount,
            totalBytesText: formattedBytes(Double(totalBytes)),
            message: message,
            chrome: req.siteChrome()
        )
        return try await req.renderHTML("favicons", context, status: status)
    }

    private func renderInternetArchive(
        _ req: Request,
        admin: User,
        message: String?,
        error: String? = nil,
        status: HTTPResponseStatus = .ok
    ) async throws -> Response {
        async let archivedCount = Bookmark.query(on: req.db).filter(\.$waybackStatus == .archived).count()
        async let pendingCount = Bookmark.query(on: req.db).filter(\.$waybackStatus == .pending).count()
        async let failedCount = Bookmark.query(on: req.db).filter(\.$waybackStatus == .failed).count()
        async let notSubmittedCount = Bookmark.query(on: req.db).filter(\.$waybackStatus == .none).count()

        let (archived, pending, failed, notSubmitted) = try await (
            archivedCount,
            pendingCount,
            failedCount,
            notSubmittedCount
        )

        let enabled = WaybackSubmitter.isInstanceEnabled(on: req.application)
        let state = await req.application.storage[WaybackWorkerKey.self]?.currentState() ?? .idle
        let queueStatus = Self.queueStatusText(enabled: enabled, pendingCount: pending, state: state)

        let context = InternetArchiveAdminContext(
            title: "Internet Archive",
            adminUsername: admin.username,
            internetArchiveEnabled: enabled,
            queueStatus: queueStatus,
            totalCount: archived + pending + failed + notSubmitted,
            archivedCount: archived,
            pendingCount: pending,
            failedCount: failed,
            notSubmittedCount: notSubmitted,
            message: message,
            error: error,
            chrome: req.siteChrome()
        )
        return try await req.renderHTML("internet-archive", context, status: status)
    }

    private func renderHealth(
        _ req: Request,
        message: String?,
        error: String?,
        status: HTTPResponseStatus = .ok
    ) async throws -> Response {
        let admin = try req.auth.require(User.self)

        let version = req.application.storage[AppVersionKey.self] ?? "dev"
        let (dbStatusText, dbOK, driverName) = await checkDatabase(req)
        let uptime = formattedUptime(req: req)
        let disk = diskUsageSummary(req: req)

        let users = try await User.query(on: req.db).sort(\.$username).all()
        let rows = try users.map { try $0.asRow() }
        let totalBookmarks = rows.reduce(0) { $0 + $1.bookmarkCount }

        let updateStatus = req.application.storage[UpdateStatusCacheKey.self]?.current
        let lastCheckedText = updateStatus?.lastCheckedAt.map { DateFormatter.webDateTime.string(from: $0) }

        let context = HealthContext(
            title: "Health",
            adminUsername: admin.username,
            version: version,
            dbStatusText: dbStatusText,
            dbIsOK: dbOK,
            dbDriver: driverName,
            uptime: uptime,
            diskUsageText: disk,
            totalUsers: users.count,
            totalBookmarks: totalBookmarks,
            updateCheckEnabled: req.application.storage[SiteSettingsCacheKey.self]?.current.updateCheckEnabled ?? true,
            updateAvailable: updateStatus?.updateAvailable ?? false,
            updateCheckFailed: updateStatus?.checkFailed ?? false,
            latestVersion: updateStatus?.latestVersion,
            updateReleaseURL: updateStatus?.releaseURL,
            lastCheckedText: lastCheckedText,
            message: message,
            error: error,
            chrome: req.siteChrome()
        )
        return try await req.renderHTML("health", context, status: status)
    }

    private func renderBackup(
        _ req: Request,
        message: String?,
        error: String?,
        status: HTTPResponseStatus = .ok
    ) async throws -> Response {
        let admin = try req.auth.require(User.self)

        let users = try await User.query(on: req.db).all()
        let rows = try users.map { try $0.asRow() }
        let totalBookmarks = rows.reduce(0) { $0 + $1.bookmarkCount }

        let context = BackupContext(
            title: "Backup & Restore",
            adminUsername: admin.username,
            userCount: users.count,
            totalBookmarks: totalBookmarks,
            message: message,
            error: error,
            chrome: req.siteChrome()
        )
        return try await req.renderHTML("backup", context, status: status)
    }

    private func renderAppearance(
        _ req: Request,
        admin: User,
        accentTheme: String,
        aboutText: String,
        footerLinks: [FooterLink],
        error: String?,
        message: String?,
        status: HTTPResponseStatus = .ok
    ) async throws -> Response {
        let themes = AccentTheme.all.map {
            ThemeOption(id: $0.id, name: $0.name, light: $0.light, dark: $0.dark, isSelected: $0.id == accentTheme)
        }
        var padded = footerLinks
        while padded.count < 4 {
            padded.append(FooterLink(label: "", url: ""))
        }
        let context = AppearanceContext(
            title: "Appearance",
            adminUsername: admin.username,
            themes: themes,
            aboutText: aboutText,
            footerLink0Label: padded[0].label,
            footerLink0URL: padded[0].url,
            footerLink1Label: padded[1].label,
            footerLink1URL: padded[1].url,
            footerLink2Label: padded[2].label,
            footerLink2URL: padded[2].url,
            footerLink3Label: padded[3].label,
            footerLink3URL: padded[3].url,
            error: error,
            message: message,
            chrome: req.siteChrome()
        )
        return try await req.renderHTML("appearance", context, status: status)
    }

    private func loadUser(_ req: Request) async throws -> User? {
        guard let id = req.parameters.get("userID", as: UUID.self) else { return nil }

        return try await User.find(id, on: req.db)
    }

    private func renderDetail(
        _ req: Request,
        user: User,
        error: String?,
        message: String?,
        status: HTTPResponseStatus = .ok
    ) async throws -> Response {
        let admin = try req.auth.require(User.self)
        let isSelf = try user.requireID() == admin.requireID()
        let context = try UserDetailContext(
            title: user.username,
            adminUsername: admin.username,
            user: user.asRow(),
            createdAt: DateFormatter.webDateTime.string(from: user.createdAt ?? Date()),
            isSelf: isSelf,
            error: error,
            message: message,
            chrome: req.siteChrome()
        )
        return try await req.renderHTML("user-detail", context, status: status)
    }
}

private extension User {

    func asRow() throws -> UserRowContext {
        try UserRowContext(
            id: requireID().uuidString,
            username: username,
            role: role.rawValue,
            isActive: isActive,
            bookmarkCount: bookmarkCount,
            isTOTPEnabled: isTOTPEnabled
        )
    }
}
