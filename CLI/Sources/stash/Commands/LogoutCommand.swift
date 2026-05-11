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
