import Vapor

// MARK: - Form inputs (application/x-www-form-urlencoded)

/// `POST /admin/login` form. TOTP is only required if the admin has 2FA enabled.
struct LoginForm: Content {
    let username: String
    let password: String
    let totpCode: String?
}

/// `POST /admin/users/new` form. Note there is deliberately no `role` field — accounts created
/// from the dashboard are always regular users (same rule as the API, PRD §4).
struct CreateUserForm: Content {
    let username: String
    let password: String
}

/// `POST /admin/users/:id/reset-password` form.
struct ResetPasswordForm: Content {
    let password: String
}

// MARK: - Leaf view contexts

/// A user row shown in tables and on the detail page.
struct UserRowContext: Content {
    let id: String
    let username: String
    let role: String
    let isActive: Bool
    let bookmarkCount: Int
    let isTOTPEnabled: Bool
}

struct LoginPageContext: Content {
    let title: String
    let error: String?
}

struct DashboardContext: Content {
    let title: String
    let adminUsername: String
    let totalUsers: Int
    let totalBookmarks: Int
    let users: [UserRowContext]
}

struct UsersContext: Content {
    let title: String
    let adminUsername: String
    let users: [UserRowContext]
}

struct NewUserContext: Content {
    let title: String
    let adminUsername: String
    let error: String?
    let username: String?
}

struct UserDetailContext: Content {
    let title: String
    let adminUsername: String
    let user: UserRowContext
    let createdAt: String
    let isSelf: Bool
    let error: String?
    let message: String?
}
