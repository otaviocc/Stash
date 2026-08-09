// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Vapor

/// Strongly-typed API errors that serialize to the standard envelope (Docs/product-technical.md §19.4).
enum APIError: AbortError {

    case invalidCredentials
    case accountSuspended
    case tokenExpired
    case tokenInvalid
    case totpRequired
    case totpInvalid
    case forbidden
    case notFound
    case smartViewNotFound
    case duplicateURL(existingID: UUID)
    case usernameTaken
    case cannotDeleteSelf
    case cannotSuspendSelf
    case validationFailed(String)
    case internalError
    case custom(status: HTTPResponseStatus, code: String, message: String)

    // MARK: Computed Properties

    var status: HTTPResponseStatus {
        switch self {
        case .invalidCredentials, .accountSuspended, .tokenExpired, .tokenInvalid,
             .totpRequired, .totpInvalid:
            .unauthorized
        case .forbidden:
            .forbidden
        case .notFound, .smartViewNotFound:
            .notFound
        case .duplicateURL, .usernameTaken:
            .conflict
        case .cannotDeleteSelf, .cannotSuspendSelf:
            .badRequest
        case .validationFailed:
            .unprocessableEntity
        case .internalError:
            .internalServerError
        case let .custom(status, _, _):
            status
        }
    }

    var code: String {
        switch self {
        case .invalidCredentials: "invalid_credentials"
        case .accountSuspended: "account_suspended"
        case .tokenExpired: "token_expired"
        case .tokenInvalid: "token_invalid"
        case .totpRequired: "totp_required"
        case .totpInvalid: "totp_invalid"
        case .forbidden: "forbidden"
        case .notFound: "not_found"
        case .smartViewNotFound: "smart_view_not_found"
        case .duplicateURL: "duplicate_url"
        case .usernameTaken: "username_taken"
        case .cannotDeleteSelf: "cannot_delete_self"
        case .cannotSuspendSelf: "cannot_suspend_self"
        case .validationFailed: "validation_failed"
        case .internalError: "internal_error"
        case let .custom(_, code, _): code
        }
    }

    var reason: String {
        switch self {
        case .invalidCredentials: "Wrong username or password."
        case .accountSuspended: "This account is suspended."
        case .tokenExpired: "The access token has expired."
        case .tokenInvalid: "The token is malformed or unrecognized."
        case .totpRequired: "Two-factor authentication is required."
        case .totpInvalid: "The TOTP or recovery code is invalid."
        case .forbidden: "You do not have permission to perform this action."
        case .notFound: "The requested resource does not exist."
        case .smartViewNotFound: "The requested Smart View does not exist."
        case .duplicateURL: "This URL has already been saved."
        case .usernameTaken: "That username is already taken."
        case .cannotDeleteSelf: "An admin cannot delete their own account."
        case .cannotSuspendSelf: "An admin cannot suspend their own account."
        case let .validationFailed(message): message
        case .internalError: "An unexpected error occurred."
        case let .custom(_, _, message): message
        }
    }
}
