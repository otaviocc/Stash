// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Vapor

// MARK: - LoginForm

/// `POST /admin/login` form. TOTP is only required if the admin has 2FA enabled.
struct LoginForm: Content {

    let username: String
    let password: String
    let totpCode: String?
}

// MARK: - CreateUserForm

/// `POST /admin/users/new` form. Note there is deliberately no `role` field — accounts created
/// from the dashboard are always regular users (same rule as the API, PRD §4).
struct CreateUserForm: Content {

    let username: String
    let password: String
}

// MARK: - ResetPasswordForm

/// `POST /admin/users/:id/reset-password` form.
struct ResetPasswordForm: Content {

    let password: String
}

// MARK: - UserRowContext

/// A user row shown in tables and on the detail page.
struct UserRowContext: Content {

    let id: String
    let username: String
    let role: String
    let isActive: Bool
    let bookmarkCount: Int
    let isTOTPEnabled: Bool
}

// MARK: - LoginPageContext

/// View context for the admin login page.
struct LoginPageContext: Content {

    let title: String
    let error: String?
    let chrome: SiteChrome
}

// MARK: - DashboardContext

/// View context for the admin dashboard page.
struct DashboardContext: Content {

    let title: String
    let adminUsername: String
    let totalUsers: Int
    let totalBookmarks: Int
    let users: [UserRowContext]
    let chrome: SiteChrome
}

// MARK: - HealthContext

/// View context for the admin health page. Every field here is safe to show only to a signed-in
/// admin — this is deliberately a *different* surface than the public, unversioned `GET /health`
/// JSON endpoint, which must keep returning only `{ "status": "ok" }` and nothing more.
struct HealthContext: Content {

    let title: String
    let adminUsername: String
    let version: String
    let dbStatusText: String
    let dbIsOK: Bool
    let dbDriver: String
    let uptime: String
    let diskUsageText: String
    let totalUsers: Int
    let totalBookmarks: Int
    let chrome: SiteChrome
}

// MARK: - MaintenanceContext

/// View context for the admin maintenance page (database optimize / VACUUM).
struct MaintenanceContext: Content {

    let title: String
    let adminUsername: String
    let message: String?
    let error: String?
    let chrome: SiteChrome
}

// MARK: - UsersContext

/// View context for the admin users list page.
struct UsersContext: Content {

    let title: String
    let adminUsername: String
    let users: [UserRowContext]
    let chrome: SiteChrome
}

// MARK: - NewUserContext

/// View context for the new-user form page.
struct NewUserContext: Content {

    let title: String
    let adminUsername: String
    let error: String?
    let username: String?
    let chrome: SiteChrome
}

// MARK: - UserDetailContext

/// View context for the user detail page.
struct UserDetailContext: Content {

    let title: String
    let adminUsername: String
    let user: UserRowContext
    let createdAt: String
    let isSelf: Bool
    let error: String?
    let message: String?
    let chrome: SiteChrome
}

// MARK: - AuditLogRowContext

/// A single audit-log row shown in the admin audit viewer.
struct AuditLogRowContext: Content {

    let time: String
    let actor: String
    let action: String
    let detail: String
}

// MARK: - AuditLogContext

/// View context for the admin audit-log page.
struct AuditLogContext: Content {

    let title: String
    let adminUsername: String
    let entries: [AuditLogRowContext]
    let chrome: SiteChrome
}

// MARK: - SessionRowWebContext

/// A live session row shown in the admin sessions viewer.
struct SessionRowWebContext: Content {

    let id: String
    let userID: String
    let username: String?
    let sessionType: String
    let userIsActive: Bool
}

// MARK: - RevokeUserSessionsForm

/// `POST /admin/sessions/revoke-user` form.
struct RevokeUserSessionsForm: Content {

    let userName: String
}

// MARK: - SessionsContext

/// View context for the admin active-sessions page.
struct SessionsContext: Content {

    let title: String
    let adminUsername: String
    let sessions: [SessionRowWebContext]
    let total: Int
    let message: String?
    let error: String?
    let chrome: SiteChrome
}

// MARK: - FaviconAdminContext

/// View context for the admin favicon cache management page.
struct FaviconAdminContext: Content {

    let title: String
    let adminUsername: String
    let totalCount: Int
    let cachedCount: Int
    let pendingCount: Int
    let failedCount: Int
    let totalBytesText: String
    let message: String?
    let chrome: SiteChrome
}
