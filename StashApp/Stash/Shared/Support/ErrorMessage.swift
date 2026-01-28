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
