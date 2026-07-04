// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation

// MARK: - Config

/// `stash config` — view and edit the persisted CLI configuration.
struct Config: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "View and edit the CLI configuration.",
        subcommands: [
            ConfigSetURL.self,
            ConfigSetToken.self,
            ConfigShow.self
        ]
    )
}

// MARK: - ConfigSetURL

/// `stash config set-url <url>` — save the server base URL.
struct ConfigSetURL: AsyncParsableCommand {

    // MARK: Static Properties

    static let configuration = CommandConfiguration(
        commandName: "set-url",
        abstract: "Save the server base URL to the config."
    )

    // MARK: Properties

    @Argument(help: "The server base URL, e.g. http://localhost:8080")
    var url: String

    // MARK: Functions

    func run() async throws {
        try await runCLI {
            guard let parsed = URL(string: url), parsed.scheme != nil, parsed.host != nil else {
                throw CLIError("Invalid URL: \(url)")
            }

            let store = ConfigStore()
            var config = try store.load()
            config.baseURL = parsed
            try store.save(config)

            Console.out("Server URL set to \(parsed.absoluteString).")
        }
    }
}

// MARK: - ConfigSetToken

/// `stash config set-token <token>` — save an access token manually (for scripting).
struct ConfigSetToken: AsyncParsableCommand {

    // MARK: Static Properties

    static let configuration = CommandConfiguration(
        commandName: "set-token",
        abstract: "Save an access token manually (for scripting)."
    )

    // MARK: Properties

    @Argument(help: "The access token.")
    var token: String

    // MARK: Functions

    func run() async throws {
        try await runCLI {
            let store = ConfigStore()
            var config = try store.load()
            config.accessToken = token
            try store.save(config)

            Console.out("Access token saved.")
        }
    }
}

// MARK: - ConfigShow

/// `stash config show` — print the current config with tokens masked.
struct ConfigShow: AsyncParsableCommand {

    // MARK: Static Properties

    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Print the current config (tokens masked)."
    )

    // MARK: Functions

    func run() async throws {
        try await runCLI {
            let config = try ConfigStore().load()

            Console.out("Server URL:    \(config.baseURL?.absoluteString ?? "(not set)")")
            Console.out("Access token:  \(mask(config.accessToken))")
            Console.out("Refresh token: \(mask(config.refreshToken))")
        }
    }

    private func mask(_ value: String?) -> String {
        guard let value, !value.isEmpty else {
            return "(not set)"
        }

        return String(value.prefix(8)) + "…"
    }
}
