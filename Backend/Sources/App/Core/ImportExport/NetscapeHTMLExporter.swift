// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation

/// Exports all of a user's bookmarks (archived included) as a Netscape Bookmark File
/// (`<!DOCTYPE NETSCAPE-Bookmark-file-1>`), importable by every browser and most bookmark
/// managers.
///
/// Stash tags are hierarchical *and* multi-valued per bookmark, while a Netscape file's folders
/// are a strict single-parent tree — there's no lossless way to place a multi-tagged bookmark
/// into one folder. So this export is intentionally **flat** (a single top-level list, no
/// folders) and instead writes every tag into the bookmark's non-standard but widely-supported
/// `TAGS="a,b,c"` attribute (the same convention Pinboard/Delicious use), which `NetscapeHTMLImporter`
/// reads back losslessly on a round-trip.
///
/// `isArchived` and Smart Views have no equivalent in this format and are dropped, same as
/// `AnyboxExporter`.
struct NetscapeHTMLExporter: BookmarkExporter {

    // MARK: Static Properties

    static let identifier = "netscape-html"
    static let displayName = "Browser Bookmarks (HTML)"
    static let fileExtension = "html"
    static let mimeType = "text/html"

    // MARK: Static Functions

    private static func escapeText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeAttribute(_ text: String) -> String {
        escapeText(text).replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: Functions

    func export(for userID: UUID, on db: any Database) async throws -> Data {
        let bookmarks = try await ExportSupport.sortedBookmarks(for: userID, on: db)

        var lines: [String] = [
            "<!DOCTYPE NETSCAPE-Bookmark-file-1>",
            "<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">",
            "<TITLE>Bookmarks</TITLE>",
            "<H1>Bookmarks</H1>",
            "<DL><p>"
        ]

        for bookmark in bookmarks {
            let addDate = Int(bookmark.createdAt?.timeIntervalSince1970 ?? Date().timeIntervalSince1970)
            let tagsAttribute = bookmark.tags.isEmpty ? "" : " TAGS=\"\(Self.escapeAttribute(bookmark.tags.joined(separator: ",")))\""
            lines.append(
                "    <DT><A HREF=\"\(Self.escapeAttribute(bookmark.url))\" ADD_DATE=\"\(addDate)\"\(tagsAttribute)>\(Self.escapeText(bookmark.title))</A>"
            )
            if let description = bookmark.description?.nonEmpty {
                lines.append("    <DD>\(Self.escapeText(description))")
            }
        }

        lines.append("</DL><p>")

        return Data(lines.joined(separator: "\n").utf8)
    }
}
