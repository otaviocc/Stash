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

/// Account settings for the user-facing web frontend (`/app/settings/*`): password change, 2FA
/// enrol/disable, import/export, the appearance theme cookie, and the danger-zone bulk delete.
/// Session-cookie auth via `UserSessionMiddleware`; all data access is scoped to the logged-in user.
struct SettingsWebController: RouteCollection {

    // MARK: Static Properties

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // MARK: Static Functions

    private static func currentTheme(_ req: Request) -> String {
        switch req.cookies["stash_theme"]?.string {
        case "light": "light"
        case "dark": "dark"
        default: "auto"
        }
    }

    // MARK: Functions

    func boot(routes: RoutesBuilder) throws {
        routes.get("settings", use: settings)
        routes.post("settings", "password", use: changePassword)
        routes.get("settings", "totp", use: totpSetup)
        routes.post("settings", "totp", "verify", use: totpVerify)
        routes.post("settings", "totp", "disable", use: totpDisable)
        routes.post("settings", "delete-all-bookmarks", use: deleteAllBookmarks)
        routes.post("settings", "theme", use: setTheme)

        routes.on(.POST, "import", body: .collect(maxSize: "16mb"), use: importBookmarks)
        routes.get("export", use: exportBookmarks)
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
            message: FlashMessage.app(for: req.query[String.self, at: "ok"]),
            importSummary: importSummary
        ))
    }

    func changePassword(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let form = try req.content.decode(AppChangePasswordForm.self)

        func settingsError(_ message: String) async throws -> Response {
            try await req.renderHTML("app-settings", settingsContext(req, user, error: message), status: .badRequest)
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

        return try await req.renderHTML("app-totp-setup", AppTOTPSetupContext(
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
            return try await req.renderHTML("app-totp-setup", AppTOTPSetupContext(
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

        return try await req.renderHTML("app-recovery-codes", AppRecoveryCodesContext(
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
            return try await req.renderHTML("app-settings", settingsContext(
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
            try await req.renderHTML(
                "app-settings",
                settingsContext(req, user, importError: message),
                status: .badRequest
            )
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
            return try await req.renderHTML("app-settings", settingsContext(
                req, user, error: "Type “delete all” to confirm — no bookmarks were deleted."
            ), status: .badRequest)
        }

        let userID = try user.requireID()
        let bookmarkIDs = try await user.$bookmarks.query(on: req.db).all().map { try $0.requireID() }

        try await req.db.transaction { db in
            try await user.$bookmarks.query(on: db).delete()
            for bookmarkID in bookmarkIDs {
                try await DeletedBookmark.record(bookmarkID: bookmarkID, userID: userID, on: db)
            }
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

    // MARK: - Helpers

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
}
