import Vapor

/// The role of an account. There is exactly one `admin`; everyone else is a `user`.
enum UserRole: String, Codable {
    case admin
    case user
}
