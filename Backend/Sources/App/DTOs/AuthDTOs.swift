import Vapor

// MARK: - Requests

struct LoginRequest: Content, Validatable {
    let username: String
    let password: String

    static func validations(_ validations: inout Validations) {
        validations.add("username", as: String.self, is: !.empty)
        validations.add("password", as: String.self, is: !.empty)
    }
}

struct TOTPRequest: Content {
    let tempToken: String
    let totpCode: String
}

struct RecoveryRequest: Content {
    let tempToken: String
    let recoveryCode: String
}

struct RefreshRequest: Content {
    let refreshToken: String
}

struct LogoutRequest: Content {
    let refreshToken: String
}

struct VerifySetupRequest: Content {
    let totpCode: String
}

struct ChangePasswordRequest: Content, Validatable {
    let currentPassword: String
    let newPassword: String

    static func validations(_ validations: inout Validations) {
        validations.add("newPassword", as: String.self, is: .count(12...))
    }
}

// MARK: - Responses

/// Successful authentication result (PRD §8.2).
struct TokenPair: Content {
    let accessToken: String
    let refreshToken: String
}

/// Login result when 2FA is enabled (PRD §8.2).
struct TwoFactorRequired: Content {
    let requires2FA: Bool
    let tempToken: String

    init(tempToken: String) {
        self.requires2FA = true
        self.tempToken = tempToken
    }
}

struct TOTPSetupResponse: Content {
    let secret: String
    let otpauthURI: String
}

struct RecoveryCodesResponse: Content {
    let recoveryCodes: [String]
}

/// Public user projection (PRD §13 `User`).
struct UserResponse: Content {
    let id: UUID
    let username: String
    let role: UserRole
    let isActive: Bool
    let isTOTPEnabled: Bool
    let bookmarkCount: Int
    let createdAt: Date
}

struct HealthResponse: Content {
    let status: String
}
