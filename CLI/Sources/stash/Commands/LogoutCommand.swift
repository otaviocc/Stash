// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import StashKit

/// `stash logout` — invalidate the stored refresh token and clear local credentials.
struct Logout: AsyncParsableCommand {

    // MARK: Static Properties

    static let configuration = CommandConfiguration(
        commandName: "logout",
        abstract: "Log out and clear stored credentials."
    )

    // MARK: Functions

    func run() async throws {
        try await runCLI {
            let store = ConfigStore()
            var config = try store.load()

            if let baseURL = config.baseURL, let refreshToken = config.refreshToken {
                let client = CLIRuntime.unauthenticatedClient(baseURL: baseURL)
                _ = try? await client.run(AuthRequestFactory.makeLogoutRequest(refreshToken: refreshToken))
            }

            config.accessToken = nil
            config.refreshToken = nil
            try store.save(config)

            Console.out("Logged out.")
        }
    }
}
