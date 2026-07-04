// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import ArgumentParser

/// The `stash` command-line interface root command.
///
/// Bookmark and tag subcommands are also exposed as top-level aliases (`stash list`, `stash add`,
/// `stash get`, `stash delete`, `stash archive`) for convenience, in addition to their grouped
/// forms (`stash bookmarks list`, …).
@main
struct Stash: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "stash",
        abstract: "A command-line interface for the Stash bookmark manager.",
        subcommands: [
            Config.self,
            Login.self,
            Logout.self,
            Bookmarks.self,
            Tags.self,
            SmartViews.self,
            ImportCommand.self,
            ExportCommand.self,
            Admin.self,
            BookmarksList.self,
            BookmarksAdd.self,
            BookmarksGet.self,
            BookmarksDelete.self,
            BookmarksArchive.self
        ]
    )
}
