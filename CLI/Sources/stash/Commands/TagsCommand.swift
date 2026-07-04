// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import StashKit

// MARK: - Tags

/// `stash tags` — list, rename, and delete tags. Defaults to listing when no subcommand is given.
struct Tags: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "tags",
        abstract: "Manage tags.",
        subcommands: [
            TagsList.self,
            TagsRename.self,
            TagsDelete.self
        ],
        defaultSubcommand: TagsList.self
    )
}

// MARK: - TagsList

/// `stash tags list` — list all tags with counts.
struct TagsList: AsyncParsableCommand {

    // MARK: Static Properties

    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all tags with counts."
    )

    // MARK: Properties

    @Flag(name: .customLong("json"), help: "Output as JSON.")
    var json = false

    // MARK: Functions

    func run() async throws {
        try await runCLI {
            let client = try await CLIRuntime.authenticatedClient(store: ConfigStore())
            let tags = try await client.run(TagRequestFactory.makeListRequest()).value

            if json {
                try Console.out(OutputFormatter.json(tags))
            } else if tags.isEmpty {
                Console.out("No tags found.")
            } else {
                for tag in tags {
                    Console.out("\(tag.name) (\(tag.count))")
                }
            }
        }
    }
}

// MARK: - TagsRename

/// `stash tags rename --from <tag> --to <tag>` — rename a tag and its children.
struct TagsRename: AsyncParsableCommand {

    // MARK: Static Properties

    static let configuration = CommandConfiguration(
        commandName: "rename",
        abstract: "Rename a tag and its children."
    )

    // MARK: Properties

    @Option(name: .customLong("from"), help: "The current tag name.")
    var from: String

    @Option(name: .customLong("to"), help: "The new tag name.")
    var to: String

    // MARK: Functions

    func run() async throws {
        try await runCLI {
            let client = try await CLIRuntime.authenticatedClient(store: ConfigStore())
            let body = TagRenameRequest(from: from, to: to)
            let result = try await client.run(TagRequestFactory.makeRenameRequest(body)).value

            Console.out("Renamed \(result.from) to \(result.to) (\(result.affectedBookmarks) bookmarks updated).")
        }
    }
}

// MARK: - TagsDelete

/// `stash tags delete <tag>` — delete a tag and its children.
struct TagsDelete: AsyncParsableCommand {

    // MARK: Static Properties

    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a tag and its children."
    )

    // MARK: Properties

    @Argument(help: "The tag name.")
    var tag: String

    @Flag(name: .customLong("force"), help: "Skip the confirmation prompt.")
    var force = false

    // MARK: Functions

    func run() async throws {
        try await runCLI {
            guard force || Console.confirm("Delete tag \(tag) and all its children? [y/N] ") else {
                Console.out("Cancelled.")

                return
            }

            let client = try await CLIRuntime.authenticatedClient(store: ConfigStore())
            let result = try await client.run(TagRequestFactory.makeDeleteRequest(tag: tag)).value

            Console.out("Deleted tag \(result.tag) (\(result.affectedBookmarks) bookmarks updated).")
        }
    }
}
