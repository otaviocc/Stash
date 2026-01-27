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
