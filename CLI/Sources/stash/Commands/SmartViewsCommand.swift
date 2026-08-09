// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import StashKit

// MARK: - SmartViews

/// `stash smart-views`: list Smart Views and run their saved queries. Consumption only; creating and
/// editing Smart Views is done from the web frontend (and round-trips through `stash import`/`export`).
/// Defaults to listing when no subcommand is given.
struct SmartViews: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "smart-views",
        abstract: "Browse Smart Views and the bookmarks they match.",
        subcommands: [
            SmartViewsList.self,
            SmartViewsBookmarks.self
        ],
        defaultSubcommand: SmartViewsList.self
    )
}

// MARK: - SmartViewsList

/// `stash smart-views list`: list all Smart Views with their match mode and conditions.
struct SmartViewsList: AsyncParsableCommand {

    // MARK: Static Properties

    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all Smart Views."
    )

    // MARK: Properties

    @Flag(name: .customLong("json"), help: "Output as JSON.")
    var json = false

    // MARK: Functions

    func run() async throws {
        try await runCLI {
            let client = try await CLIRuntime.authenticatedClient(store: ConfigStore())
            let smartViews = try await client.run(SmartViewRequestFactory.makeListRequest()).value

            if json {
                try Console.out(OutputFormatter.json(smartViews))
            } else {
                Console.out(OutputFormatter.smartViewsTable(smartViews))
            }
        }
    }
}

// MARK: - SmartViewsBookmarks

/// `stash smart-views bookmarks <id>`: run a Smart View's saved query and list the matching bookmarks.
struct SmartViewsBookmarks: AsyncParsableCommand {

    // MARK: Static Properties

    static let configuration = CommandConfiguration(
        commandName: "bookmarks",
        abstract: "List the bookmarks a Smart View matches."
    )

    // MARK: Properties

    @Argument(help: "The Smart View UUID (from `stash smart-views list`).")
    var id: String

    @Option(name: .customLong("page"), help: "Page number.")
    var page = 1

    @Option(name: .customLong("per"), help: "Results per page.")
    var per = 20

    @Flag(name: .customLong("json"), help: "Output raw JSON.")
    var json = false

    // MARK: Functions

    func run() async throws {
        try await runCLI {
            let smartViewID = try requireUUID(id, label: "Smart View ID")
            let client = try await CLIRuntime.authenticatedClient(store: ConfigStore())
            let pageDTO = try await client.run(
                SmartViewRequestFactory.makeBookmarksRequest(id: smartViewID, page: page, perPage: per)
            ).value

            if json {
                try Console.out(OutputFormatter.json(pageDTO))
            } else {
                Console.out(OutputFormatter.bookmarksTable(pageDTO.items))
            }
        }
    }
}
