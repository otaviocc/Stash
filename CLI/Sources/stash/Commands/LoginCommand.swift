// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import MicroClient
import StashKit

// MARK: - Login

/// `stash login`: authenticate interactively and persist the resulting tokens.
///
/// Prompts for the server URL (if not already configured), username, and a hidden password. When
/// the account has 2FA enabled the server returns a challenge, and the command then prompts for a
/// TOTP code before completing the login.
struct Login: AsyncParsableCommand {

    // MARK: Static Properties

    static let configuration = CommandConfiguration(
        commandName: "login",
        abstract: "Authenticate with the Stash server."
    )

    // MARK: Functions

    func run() async throws {
        try await runCLI {
            let store = ConfigStore()
            var config = try store.load()
            let baseURL = try resolveBaseURL(config: &config, store: store)

            let username = try requireInput(Console.prompt("Username: "), label: "Username")
            let password = Console.promptHidden("Password: ")

            let client = CLIRuntime.unauthenticatedClient(baseURL: baseURL)
            let outcome = try await client
                .run(LoginOutcome.makeRequest(username: username, password: password))
                .value

            let tokens = try await completeLogin(outcome, username: username, client: client)

            config.accessToken = tokens.access
            config.refreshToken = tokens.refresh
            try store.save(config)

            Console.out("Logged in as \(username).")
        }
    }

    private func resolveBaseURL(config: inout CLIConfig, store: ConfigStore) throws -> URL {
        if let baseURL = config.baseURL {
            return baseURL
        }

        let entered = try requireInput(Console.prompt("Server URL: "), label: "Server URL")
        guard let url = URL(string: entered), url.scheme != nil, url.host != nil else {
            throw CLIError("Invalid URL: \(entered)")
        }

        config.baseURL = url
        try store.save(config)

        return url
    }

    private func completeLogin(
        _ outcome: LoginOutcome,
        username: String,
        client: StashClient
    ) async throws -> (access: String, refresh: String) {
        if outcome.requires2FA == true {
            guard let tempToken = outcome.tempToken else {
                throw CLIError("The server requested 2FA but returned no token.")
            }

            let code = try requireInput(Console.prompt("2FA code: "), label: "2FA code")
            let pair = try await client
                .run(AuthRequestFactory.makeTOTPRequest(tempToken: tempToken, code: code))
                .value

            return (pair.accessToken, pair.refreshToken)
        }

        guard let accessToken = outcome.accessToken, let refreshToken = outcome.refreshToken else {
            throw CLIError("The server returned an unexpected login response.")
        }

        return (accessToken, refreshToken)
    }

    private func requireInput(_ value: String?, label: String) throws -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CLIError("\(label) is required.")
        }

        return value
    }
}

// MARK: - LoginOutcome

/// Decodes either shape of a successful login response: a token pair, or a 2FA challenge.
///
/// StashKit's typed login factory returns only `TokenPairDTO`, which cannot represent the
/// 2FA-challenge branch, so the CLI builds its own request against the same endpoint.
struct LoginOutcome: Decodable {

    // MARK: Properties

    let accessToken: String?
    let refreshToken: String?
    let requires2FA: Bool?
    let tempToken: String?

    // MARK: Static Functions

    static func makeRequest(
        username: String,
        password: String
    ) -> NetworkRequest<LoginRequest, LoginOutcome> {
        .init(
            path: "/api/v1/auth/login",
            method: .post,
            body: LoginRequest(username: username, password: password)
        )
    }
}
