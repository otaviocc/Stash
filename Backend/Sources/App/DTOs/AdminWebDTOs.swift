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

struct LoginPageContext: Content {

    let title: String
    let error: String?
}

// MARK: - DashboardContext

struct DashboardContext: Content {

    let title: String
    let adminUsername: String
    let totalUsers: Int
    let totalBookmarks: Int
    let users: [UserRowContext]
}

// MARK: - UsersContext

struct UsersContext: Content {

    let title: String
    let adminUsername: String
    let users: [UserRowContext]
}

// MARK: - NewUserContext

struct NewUserContext: Content {

    let title: String
    let adminUsername: String
    let error: String?
    let username: String?
}

// MARK: - UserDetailContext

struct UserDetailContext: Content {

    let title: String
    let adminUsername: String
    let user: UserRowContext
    let createdAt: String
    let isSelf: Bool
    let error: String?
    let message: String?
}
