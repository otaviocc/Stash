import Vapor

/// Strongly-typed API errors that serialise to the standard envelope (PRD §17.4).
enum APIError: AbortError {
    case invalidCredentials
    case accountSuspended
    case tokenExpired
    case tokenInvalid
    case totpRequired
    case totpInvalid
    case forbidden
    case notFound
    case duplicateURL(existingID: UUID)
    case validationFailed(String)
    case internalError
    case custom(status: HTTPResponseStatus, code: String, message: String)

    var status: HTTPResponseStatus {
        switch self {
        case .invalidCredentials, .accountSuspended, .tokenExpired, .tokenInvalid,
             .totpRequired, .totpInvalid:
            return .unauthorized
        case .forbidden:
            return .forbidden
        case .notFound:
            return .notFound
        case .duplicateURL:
            return .conflict
        case .validationFailed:
            return .unprocessableEntity
        case .internalError:
            return .internalServerError
        case let .custom(status, _, _):
            return status
        }
    }

    /// The snake_case error code from the PRD's standard error-code table.
    var code: String {
        switch self {
        case .invalidCredentials: return "invalid_credentials"
        case .accountSuspended: return "account_suspended"
        case .tokenExpired: return "token_expired"
        case .tokenInvalid: return "token_invalid"
        case .totpRequired: return "totp_required"
        case .totpInvalid: return "totp_invalid"
        case .forbidden: return "forbidden"
        case .notFound: return "not_found"
        case .duplicateURL: return "duplicate_url"
        case .validationFailed: return "validation_failed"
        case .internalError: return "internal_error"
        case let .custom(_, code, _): return code
        }
    }

    var reason: String {
        switch self {
        case .invalidCredentials: return "Wrong username or password."
        case .accountSuspended: return "This account is suspended."
        case .tokenExpired: return "The access token has expired."
        case .tokenInvalid: return "The token is malformed or unrecognised."
        case .totpRequired: return "Two-factor authentication is required."
        case .totpInvalid: return "The TOTP or recovery code is invalid."
        case .forbidden: return "You do not have permission to perform this action."
        case .notFound: return "The requested resource does not exist."
        case .duplicateURL: return "This URL has already been saved."
        case let .validationFailed(message): return message
        case .internalError: return "An unexpected error occurred."
        case let .custom(_, _, message): return message
        }
    }
}
