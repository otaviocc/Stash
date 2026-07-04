// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import StashKit

// MARK: - Bookmarks

/// `stash bookmarks` — manage bookmarks. Subcommands are also exposed as top-level aliases.
struct Bookmarks: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "bookmarks",
        abstract: "Manage bookmarks.",
        subcommands: [
            BookmarksList.self,
            BookmarksAdd.self,
            BookmarksGet.self,
            BookmarksDelete.self,
            BookmarksArchive.self
        ],
        defaultSubcommand: BookmarksList.self
    )
}

// MARK: - BookmarksList

/// `stash bookmarks list` (alias `stash list`) — list bookmarks as a table or JSON.
struct BookmarksList: AsyncParsableCommand {

    // MARK: Static Properties

    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List bookmarks."
    )

    // MARK: Properties

    @Option(name: .customLong("tag"), help: "Filter by tag (prefix match; use \"__untagged__\" for untagged).")
    var tag: String?

    @Option(name: .customLong("search"), help: "Full-text search query.")
    var search: String?

    @Flag(name: .customLong("archived"), help: "Show archived bookmarks.")
    var archived = false

    @Option(name: .customLong("page"), help: "Page number.")
    var page = 1

    @Option(name: .customLong("per"), help: "Results per page.")
    var per = 20

    @Flag(name: .customLong("json"), help: "Output raw JSON.")
    var json = false

    // MARK: Functions

    func run() async throws {
        try await runCLI {
            let client = try await CLIRuntime.authenticatedClient(store: ConfigStore())
            let query = BookmarkListQuery(
                searchQuery: search,
                tag: tag,
                archived: archived,
                page: page,
                perPage: per
            )
            let pageDTO = try await client.run(BookmarkRequestFactory.makeListRequest(query: query)).value

            if json {
                try Console.out(OutputFormatter.json(pageDTO))
            } else {
                Console.out(OutputFormatter.bookmarksTable(pageDTO.items))
            }
        }
    }
}

// MARK: - BookmarksAdd

/// `stash bookmarks add` (alias `stash add`) — save a new bookmark.
struct BookmarksAdd: AsyncParsableCommand {

    // MARK: Static Properties

    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Save a bookmark."
    )

    // MARK: Properties

    @Argument(help: "The URL to save.")
    var url: String

    @Option(name: .customLong("title"), help: "Override the fetched title.")
    var title: String?

    @Option(name: .customLong("description"), help: "Override the fetched description.")
    var description: String?

    @Option(name: .customLong("tag"), help: "Add a tag (repeatable).")
    var tag: [String] = []

    @Flag(name: .customLong("no-fetch"), help: "Skip metadata fetching.")
    var noFetch = false

    @Flag(name: .customLong("json"), help: "Output the created bookmark as JSON.")
    var json = false

    // MARK: Functions

    func run() async throws {
        try await runCLI {
            let client = try await CLIRuntime.authenticatedClient(store: ConfigStore())
            let body = CreateBookmarkRequest(
                url: url,
                title: title,
                description: description,
                tags: tag.isEmpty ? nil : tag,
                fetchMetadata: noFetch ? false : nil
            )
            let bookmark = try await client.run(BookmarkRequestFactory.makeCreateRequest(body)).value

            if json {
                try Console.out(OutputFormatter.json(bookmark))
            } else {
                Console.out("Saved \(bookmark.id.uuidString) — \(bookmark.title)")
            }
        }
    }
}

// MARK: - BookmarksGet

/// `stash bookmarks get` (alias `stash get`) — show a single bookmark.
struct BookmarksGet: AsyncParsableCommand {

    // MARK: Static Properties

    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Get a bookmark by ID."
    )

    // MARK: Properties

    @Argument(help: "The bookmark UUID.")
    var id: String

    @Flag(name: .customLong("json"), help: "Output as JSON.")
    var json = false

    // MARK: Functions

    func run() async throws {
        try await runCLI {
            let bookmarkID = try requireUUID(id, label: "bookmark ID")
            let client = try await CLIRuntime.authenticatedClient(store: ConfigStore())
            let bookmark = try await client.run(BookmarkRequestFactory.makeGetRequest(id: bookmarkID)).value

            if json {
                try Console.out(OutputFormatter.json(bookmark))
            } else {
                Console.out(OutputFormatter.bookmarkDetail(bookmark))
            }
        }
    }
}

// MARK: - BookmarksDelete

/// `stash bookmarks delete` (alias `stash delete`) — delete a bookmark.
struct BookmarksDelete: AsyncParsableCommand {

    // MARK: Static Properties

    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a bookmark by ID."
    )

    // MARK: Properties

    @Argument(help: "The bookmark UUID.")
    var id: String

    @Flag(name: .customLong("force"), help: "Skip the confirmation prompt.")
    var force = false

    // MARK: Functions

    func run() async throws {
        try await runCLI {
            let bookmarkID = try requireUUID(id, label: "bookmark ID")

            guard force || Console.confirm("Delete bookmark \(bookmarkID.uuidString)? [y/N] ") else {
                Console.out("Cancelled.")

                return
            }

            let client = try await CLIRuntime.authenticatedClient(store: ConfigStore())
            _ = try await client.run(BookmarkRequestFactory.makeDeleteRequest(id: bookmarkID))

            Console.out("Deleted \(bookmarkID.uuidString).")
        }
    }
}

// MARK: - BookmarksArchive

/// `stash bookmarks archive` (alias `stash archive`) — archive a bookmark.
struct BookmarksArchive: AsyncParsableCommand {

    // MARK: Static Properties

    static let configuration = CommandConfiguration(
        commandName: "archive",
        abstract: "Archive a bookmark by ID."
    )

    // MARK: Properties

    @Argument(help: "The bookmark UUID.")
    var id: String

    // MARK: Functions

    func run() async throws {
        try await runCLI {
            let bookmarkID = try requireUUID(id, label: "bookmark ID")
            let client = try await CLIRuntime.authenticatedClient(store: ConfigStore())
            let body = UpdateBookmarkRequest(isArchived: true)
            _ = try await client.run(BookmarkRequestFactory.makeUpdateRequest(id: bookmarkID, body: body))

            Console.out("Archived \(bookmarkID.uuidString).")
        }
    }
}
