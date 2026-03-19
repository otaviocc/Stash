import Vapor

// MARK: - Requests

/// `POST /admin/users` body (PRD §9.6). Accounts created here are always `user` role; any
/// `role` field in the body is silently ignored (unknown keys are dropped on decode). Admin
/// accounts can only exist via first-boot seeding (PRD §4).
struct CreateUserInput: Content, Validatable {
    let username: String
    let password: String

    static func validations(_ validations: inout Validations) {
        validations.add("username", as: String.self, is: !.empty)
        // Password rules: minimum 12 characters (PRD §8.5).
        validations.add("password", as: String.self, is: .count(12...))
    }
}

/// `PUT /admin/users/:id` body — all fields optional (PRD §9.6).
struct UpdateUserInput: Content {
    let isActive: Bool?
    let password: String?
}

// MARK: - Responses

/// One row of the aggregate stats response (PRD §13 `UserStat`).
struct UserStat: Content {
    let id: UUID
    let username: String
    let bookmarkCount: Int
    let isActive: Bool
}

/// `GET /admin/stats` response (PRD §9.6, §13 `AdminStats`).
struct AdminStatsResponse: Content {
    let totalUsers: Int
    let totalBookmarks: Int
    let users: [UserStat]
}
