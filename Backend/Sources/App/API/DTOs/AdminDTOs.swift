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

// MARK: - CreateUserInput

/// `POST /admin/users` body (PRD §9.6). Accounts created here are always `user` role; any
/// `role` field in the body is silently ignored (unknown keys are dropped on decode). Admin
/// accounts can only exist via first-boot seeding (PRD §4).
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

/// `PUT /admin/users/:id` body — all fields optional (PRD §9.6).
struct UpdateUserInput: Content {

    let isActive: Bool?
    let password: String?
}

// MARK: - UserStat

/// One row of the aggregate stats response (PRD §13 `UserStat`).
struct UserStat: Content {

    let id: UUID
    let username: String
    let bookmarkCount: Int
    let isActive: Bool
}

// MARK: - AdminStatsResponse

/// `GET /admin/stats` response (PRD §9.6, §13 `AdminStats`).
struct AdminStatsResponse: Content {

    let totalUsers: Int
    let totalBookmarks: Int
    let users: [UserStat]
}
