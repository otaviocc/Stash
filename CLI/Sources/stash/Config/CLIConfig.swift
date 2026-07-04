// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

/// The persisted configuration for the CLI.
///
/// All fields are optional so the tool degrades gracefully: a missing `baseURL` or
/// `accessToken` produces a clear "not configured / not logged in" message rather than a crash.
struct CLIConfig: Codable {

    // MARK: Properties

    var baseURL: URL?
    var accessToken: String?
    var refreshToken: String?

    // MARK: Lifecycle

    init(
        baseURL: URL? = nil,
        accessToken: String? = nil,
        refreshToken: String? = nil
    ) {
        self.baseURL = baseURL
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}
