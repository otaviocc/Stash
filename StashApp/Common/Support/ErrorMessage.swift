// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import StashKit

// MARK: - Error + UserMessage

extension Error {

    /// A human-readable, user-facing description suitable for inline error display.
    var stashUserMessage: String {
        if let error = self as? StashAPIError {
            return error.stashUserMessage
        }

        if let error = self as? AppError {
            return error.stashUserMessage
        }

        return "Something went wrong. Please try again."
    }

    /// Whether the error is a transport/connectivity failure (the server could not be reached) rather
    /// than a response the server actually returned. `StashClient` maps unreachable-host, timeout, and
    /// other transport failures to `StashAPIError.unknown`, so that case stands in for "offline". Used
    /// to route a failed write to the offline queue instead of surfacing an error.
    var isConnectivityError: Bool {
        if let error = self as? StashAPIError, case .unknown = error {
            return true
        }

        return false
    }
}

// MARK: - StashAPIError + UserMessage

extension StashAPIError {

    var stashUserMessage: String {
        switch self {
        case .invalidCredentials: "Incorrect username or password."
        case .accountSuspended: "This account has been suspended."
        case .tokenExpired, .tokenInvalid: "Your session has expired. Please sign in again."
        case .totpRequired: "Two-factor authentication is required."
        case .totpInvalid: "Incorrect code. Please try again."
        case .forbidden: "You don't have permission to do that."
        case .notFound: "That item could not be found."
        case .duplicateURL: "This URL is already saved."
        case .usernameTaken: "That username is already taken."
        case .validationFailed: "Please check the details and try again."
        case .serverError: "The server ran into a problem. Please try again."
        case .unknown: "Could not reach the server. Check the URL and your connection."
        }
    }
}

// MARK: - AppError + UserMessage

extension AppError {

    var stashUserMessage: String {
        switch self {
        case .notConfigured: "No server is configured."
        case .sessionExpired: "Your session has expired. Please sign in again."
        case .unexpectedResponse: "The server returned an unexpected response."
        }
    }
}
