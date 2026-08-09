// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Vapor

// MARK: - CreateUserInput

/// `POST /admin/users` body (Docs/product-api.md §9.7). Accounts created here are always `user` role; any
/// `role` field in the body is silently ignored (unknown keys are dropped on decode). Admin
/// accounts can only exist via first-boot seeding (Docs/product-overview.md §4).
struct CreateUserInput: Content, Validatable {

    // MARK: Properties

    let username: String
    let password: String

    // MARK: Static Functions

    static func validations(_ validations: inout Validations) {
        validations.add("username", as: String.self, is: !.empty)
        validations.add("password", as: String.self, is: .count(12...))
    }
}

// MARK: - UpdateUserInput

/// `PUT /admin/users/:id` body, all fields optional (Docs/product-api.md §9.7).
struct UpdateUserInput: Content {

    let isActive: Bool?
    let password: String?
}

// MARK: - UserStat

/// One row of the aggregate stats response (Docs/product-api.md §9.7 `UserStat`).
struct UserStat: Content {

    let id: UUID
    let username: String
    let bookmarkCount: Int
    let isActive: Bool
}

// MARK: - AdminStatsResponse

/// `GET /admin/stats` response (Docs/product-api.md §9.7 `AdminStats`).
struct AdminStatsResponse: Content {

    let totalUsers: Int
    let totalBookmarks: Int
    let users: [UserStat]
}

// MARK: - SessionRowResponse

/// One row of `GET /admin/sessions`: a live session resolved from Vapor's in-memory
/// session store (see `ActiveSessionLoader`).
struct SessionRowResponse: Content {

    let id: String
    let userID: UUID
    let username: String?
    let sessionType: String
    let userIsActive: Bool
}

// MARK: - SessionsListResponse

/// `GET /admin/sessions` response.
struct SessionsListResponse: Content {

    let sessions: [SessionRowResponse]
    let total: Int
}

// MARK: - RevokeUserSessionsInput

/// `POST /admin/sessions/revoke-user` body.
struct RevokeUserSessionsInput: Content, Validatable {

    // MARK: Properties

    let userName: String

    // MARK: Static Functions

    static func validations(_ validations: inout Validations) {
        validations.add("userName", as: String.self, is: !.empty)
    }
}
