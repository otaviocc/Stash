// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - APIErrorDTO

/// An error response returned by the API.
public struct APIErrorDTO: Codable, Sendable {

    public let error: Bool
    public let code: String
    public let message: String
    public let existingID: UUID?
}

// MARK: - StashAPIError

/// An error thrown by StashKit when the API returns a known error code.
public enum StashAPIError: Error, Sendable {

    case invalidCredentials
    case accountSuspended
    case tokenExpired
    case tokenInvalid
    case totpRequired
    case totpInvalid
    case forbidden
    case notFound
    case duplicateURL(existingID: UUID)
    case usernameTaken
    case validationFailed
    case serverError
    case unknown(Error)
}
