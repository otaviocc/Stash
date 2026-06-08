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

// MARK: - Admin

/// `stash admin` — administrative user management and statistics (admin accounts only).
struct Admin: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "admin",
        abstract: "Administrative user management.",
        subcommands: [
            AdminUsers.self,
            AdminCreateUser.self,
            AdminSuspendUser.self,
            AdminUnsuspendUser.self,
            AdminResetPassword.self,
            AdminResetTOTP.self,
            AdminDeleteUser.self,
            AdminStats.self
        ]
    )
}

// MARK: - AdminUsers

/// `stash admin users` — list all users.
struct AdminUsers: AsyncParsableCommand {

    // MARK: Static Properties

    static let configuration = CommandConfiguration(
        commandName: "users",
        abstract: "List all users."
    )

    // MARK: Properties

    @Flag(name: .customLong("json"), help: "Output as JSON.")
    var json = false

    // MARK: Functions

    func run() async throws {
        try await runCLI {
            let client = try await CLIRuntime.authenticatedClient(store: ConfigStore())
            let users = try await client.run(AdminRequestFactory.makeUsersRequest()).value

            if json {
                try Console.out(OutputFormatter.json(users))
            } else {
                Console.out(OutputFormatter.usersTable(users))
            }
        }
    }
}

// MARK: - AdminCreateUser

/// `stash admin create-user` — create a new user account.
struct AdminCreateUser: AsyncParsableCommand {

    // MARK: Static Properties

    static let configuration = CommandConfiguration(
        commandName: "create-user",
        abstract: "Create a new user."
    )

    // MARK: Properties

    @Option(name: .customLong("username"), help: "The new user's username.")
    var username: String

    @Option(name: .customLong("password"), help: "The new user's password (prompted if omitted).")
    var password: String?

    @Flag(name: .customLong("json"), help: "Output the created user as JSON.")
    var json = false

    // MARK: Functions

    func run() async throws {
        try await runCLI {
            let secret = try resolvePassword(password)
            let client = try await CLIRuntime.authenticatedClient(store: ConfigStore())
            let body = CreateUserRequest(username: username, password: secret)
            let user = try await client.run(AdminRequestFactory.makeCreateUserRequest(body)).value

            if json {
                try Console.out(OutputFormatter.json(user))
            } else {
                Console.out("Created user \(user.username).")
            }
        }
    }
}

// MARK: - AdminSuspendUser

/// `stash admin suspend-user <username>` — suspend an account.
struct AdminSuspendUser: AsyncParsableCommand {

    // MARK: Static Properties

    static let configuration = CommandConfiguration(
        commandName: "suspend-user",
        abstract: "Suspend a user account."
    )

    // MARK: Properties

    @Argument(help: "The username.")
    var username: String

    // MARK: Functions

    func run() async throws {
        try await runCLI {
            let client = try await CLIRuntime.authenticatedClient(store: ConfigStore())
            let user = try await resolveUser(username, client: client)
            let body = UpdateUserRequest(isActive: false)
            _ = try await client.run(AdminRequestFactory.makeUpdateUserRequest(id: user.id, body: body))

            Console.out("Suspended \(user.username).")
        }
    }
}

// MARK: - AdminUnsuspendUser

/// `stash admin unsuspend-user <username>` — reactivate an account.
struct AdminUnsuspendUser: AsyncParsableCommand {

    // MARK: Static Properties

    static let configuration = CommandConfiguration(
        commandName: "unsuspend-user",
        abstract: "Reactivate a suspended user account."
    )

    // MARK: Properties

    @Argument(help: "The username.")
    var username: String

    // MARK: Functions

    func run() async throws {
        try await runCLI {
            let client = try await CLIRuntime.authenticatedClient(store: ConfigStore())
            let user = try await resolveUser(username, client: client)
            let body = UpdateUserRequest(isActive: true)
            _ = try await client.run(AdminRequestFactory.makeUpdateUserRequest(id: user.id, body: body))

            Console.out("Unsuspended \(user.username).")
        }
    }
}

// MARK: - AdminResetPassword

/// `stash admin reset-password <username>` — set a new password for an account.
struct AdminResetPassword: AsyncParsableCommand {

    // MARK: Static Properties

    static let configuration = CommandConfiguration(
        commandName: "reset-password",
        abstract: "Reset a user's password."
    )

    // MARK: Properties

    @Argument(help: "The username.")
    var username: String

    @Option(name: .customLong("password"), help: "The new password (prompted if omitted).")
    var password: String?

    // MARK: Functions

    func run() async throws {
        try await runCLI {
            let secret = try resolvePassword(password)
            let client = try await CLIRuntime.authenticatedClient(store: ConfigStore())
            let user = try await resolveUser(username, client: client)
            let body = UpdateUserRequest(password: secret)
            _ = try await client.run(AdminRequestFactory.makeUpdateUserRequest(id: user.id, body: body))

            Console.out("Reset password for \(user.username).")
        }
    }
}

// MARK: - AdminResetTOTP

/// `stash admin reset-totp <username>` — clear a user's 2FA enrolment.
struct AdminResetTOTP: AsyncParsableCommand {

    // MARK: Static Properties

    static let configuration = CommandConfiguration(
        commandName: "reset-totp",
        abstract: "Reset a user's two-factor authentication."
    )

    // MARK: Properties

    @Argument(help: "The username.")
    var username: String

    // MARK: Functions

    func run() async throws {
        try await runCLI {
            let client = try await CLIRuntime.authenticatedClient(store: ConfigStore())
            let user = try await resolveUser(username, client: client)
            _ = try await client.run(AdminRequestFactory.makeResetTOTPRequest(id: user.id))

            Console.out("Reset 2FA for \(user.username).")
        }
    }
}

// MARK: - AdminDeleteUser

/// `stash admin delete-user <username>` — hard-delete an account.
struct AdminDeleteUser: AsyncParsableCommand {

    // MARK: Static Properties

    static let configuration = CommandConfiguration(
        commandName: "delete-user",
        abstract: "Hard-delete a user account."
    )

    // MARK: Properties

    @Argument(help: "The username.")
    var username: String

    @Flag(name: .customLong("force"), help: "Skip the confirmation prompt.")
    var force = false

    // MARK: Functions

    func run() async throws {
        try await runCLI {
            let client = try await CLIRuntime.authenticatedClient(store: ConfigStore())
            let user = try await resolveUser(username, client: client)

            guard force || Console.confirm("Delete user \(user.username)? [y/N] ") else {
                Console.out("Cancelled.")

                return
            }

            _ = try await client.run(AdminRequestFactory.makeDeleteUserRequest(id: user.id))

            Console.out("Deleted \(user.username).")
        }
    }
}

// MARK: - AdminStats

/// `stash admin stats` — show aggregate and per-user statistics.
struct AdminStats: AsyncParsableCommand {

    // MARK: Static Properties

    static let configuration = CommandConfiguration(
        commandName: "stats",
        abstract: "Show aggregate statistics."
    )

    // MARK: Properties

    @Flag(name: .customLong("json"), help: "Output as JSON.")
    var json = false

    // MARK: Functions

    func run() async throws {
        try await runCLI {
            let client = try await CLIRuntime.authenticatedClient(store: ConfigStore())
            let stats = try await client.run(AdminRequestFactory.makeStatsRequest()).value

            if json {
                try Console.out(OutputFormatter.json(stats))
            } else {
                Console.out(OutputFormatter.statsSummary(stats))
            }
        }
    }
}

/// Resolves a username to its account by listing users, since the admin API is keyed by UUID.
private func resolveUser(_ username: String, client: AuthorizedClient) async throws -> UserDTO {
    let users = try await client.run(AdminRequestFactory.makeUsersRequest()).value

    guard let user = users.first(where: { $0.username.lowercased() == username.lowercased() }) else {
        throw CLIError("No user named '\(username)'.")
    }

    return user
}

/// Returns the provided password, or prompts for one (hidden input) when it was omitted.
private func resolvePassword(_ password: String?) throws -> String {
    if let password, !password.isEmpty {
        return password
    }

    let entered = Console.promptHidden("Password: ")
    guard !entered.isEmpty else {
        throw CLIError("A password is required.")
    }

    return entered
}
