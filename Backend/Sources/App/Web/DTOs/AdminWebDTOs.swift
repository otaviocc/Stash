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
