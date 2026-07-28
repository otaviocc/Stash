// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation

/// Imports a Netscape Bookmark File (`<!DOCTYPE NETSCAPE-Bookmark-file-1>`) — the universal
/// browser-export format (Chrome, Firefox, Safari, Edge), also produced by Raindrop.io and
/// Pinboard's own "HTML" export options.
///
/// The format has no strict XML structure (real exports leave `<DT>`/`<p>` unclosed), so this is
/// a small hand-rolled token scanner over `<A>`/`<H3>`/`<DL>`/`</DL>`/`<DD>`, dependency-free like
/// this backend's other HTML handling (`MetadataFetcher`).
///
/// Field mapping:
/// - `HREF` (required; entry skipped if missing/invalid)
/// - The anchor's inner text → `title`
/// - A following `<DD>` line → `description`
/// - `ADD_DATE` (Unix seconds) → `createdAt`; missing/unparseable → current time
/// - Folder nesting (`<H3>` + its `<DL>`) → one hierarchical tag joined by `/`, e.g. a bookmark
///   filed under Bookmarks Bar → Github → Golang becomes tag `bookmarks bar/github/golang`. No
///   folder name is special-cased (browsers localize "Bookmarks Bar" etc.), so the tag can be
///   renamed or deleted afterward with the existing tag tools if unwanted.
/// - A non-standard `TAGS="a,b,c"` attribute (used by Pinboard/Delicious-style exporters) is
///   merged in as additional tags alongside the folder tag.
///
/// A duplicate URL updates the existing bookmark in place (title/description/tags overwritten,
/// `createdAt`/`isArchived`/`isReadLater` left untouched) — same convention as every other importer.
struct NetscapeHTMLImporter: BookmarkImporter {

    // MARK: Nested Types

    /// A single parsed bookmark entry, built up while walking the token stream.
    private struct Record {

        let href: String?
        let title: String
        var description: String?
        let tags: [String]
        let createdAt: Date?
    }

    // MARK: Static Properties

    static let identifier = "netscape-html"
    static let displayName = "Browser Bookmarks (HTML)"
    static let fileExtension = "html"

    private static let entities: [(String, String)] = [
        ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
        ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&apos;", "'"), ("&nbsp;", " ")
    ]

    // MARK: Static Functions

    private static func decodeEntities(_ text: String) -> String {
        var result = text
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }

    private static func attribute(_ pattern: String, in attrs: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }

        let range = NSRange(attrs.startIndex..., in: attrs)
        guard let match = regex.firstMatch(in: attrs, range: range),
              let group = Range(match.range(at: 1), in: attrs)
        else { return nil }

        return String(attrs[group])
    }

    private static func decodeHTML(data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    // MARK: - Parsing

    private static func parse(_ html: String) -> [Record] {
        var records: [Record] = []
        var folderStack: [String?] = []
        var pendingFolderName: String?
        var lastWasBookmark = false

        guard let token = try? NSRegularExpression(
            pattern: #"<A\s+([^>]*)>(.*?)</A>|<H3([^>]*)>(.*?)</H3>|(<DL>)|(</DL>)|<DD>([^<\r\n]*)"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }

        let range = NSRange(html.startIndex..., in: html)
        let matches = token.matches(in: html, range: range)

        for match in matches {
            if match.range(at: 1).location != NSNotFound {
                let attrs = string(at: 1, in: html, match: match) ?? ""
                let titleRaw = string(at: 2, in: html, match: match) ?? ""

                let href = attribute(#"HREF\s*=\s*"([^"]*)""#, in: attrs)
                let addDate = attribute(#"ADD_DATE\s*=\s*"([^"]*)""#, in: attrs)
                let tagsAttr = attribute(#"TAGS\s*=\s*"([^"]*)""#, in: attrs)

                let folderPath = folderStack.compactMap(\.self).joined(separator: "/")
                var tags: [String] = folderPath.isEmpty ? [] : [folderPath]
                if let tagsAttr {
                    tags += tagsAttr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                }

                let createdAt: Date? = addDate.flatMap(Double.init).map(Date.init(timeIntervalSince1970:))

                records.append(
                    Record(
                        href: href,
                        title: decodeEntities(titleRaw).trimmingCharacters(in: .whitespacesAndNewlines),
                        description: nil,
                        tags: tags,
                        createdAt: createdAt
                    )
                )
                lastWasBookmark = true
            } else if match.range(at: 4).location != NSNotFound {
                let nameRaw = string(at: 4, in: html, match: match) ?? ""
                pendingFolderName = decodeEntities(nameRaw).trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                lastWasBookmark = false
            } else if match.range(at: 5).location != NSNotFound {
                folderStack.append(pendingFolderName)
                pendingFolderName = nil
                lastWasBookmark = false
            } else if match.range(at: 6).location != NSNotFound {
                if !folderStack.isEmpty {
                    folderStack.removeLast()
                }
                lastWasBookmark = false
            } else if match.range(at: 7).location != NSNotFound {
                if lastWasBookmark, !records.isEmpty {
                    let text = string(at: 7, in: html, match: match) ?? ""
                    records[records.count - 1].description = decodeEntities(text)
                        .trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                }
                lastWasBookmark = false
            }
        }

        return records
    }

    private static func string(at group: Int, in text: String, match: NSTextCheckingResult) -> String? {
        guard let range = Range(match.range(at: group), in: text) else { return nil }

        return String(text[range])
    }

    // MARK: Functions

    func `import`(from data: Data, for userID: UUID, on db: any Database) async throws -> ImportResult {
        guard let html = Self.decodeHTML(data: data), html.lowercased().contains("netscape-bookmark-file") else {
            throw ImportError
                .invalidFormat(
                    "This doesn't look like a Netscape bookmark file (missing the NETSCAPE-Bookmark-file doctype)."
                )
        }

        let records = Self.parse(html)

        var imported = 0
        var updated = 0
        var skipped = 0
        var errors: [String] = []

        for (index, record) in records.enumerated() {
            let position = index + 1

            guard let rawHREF = record.href?.trimmingCharacters(in: .whitespacesAndNewlines), !rawHREF.isEmpty else {
                skipped += 1
                errors.append("Bookmark \(position): missing URL.")
                continue
            }

            let url: String
            do {
                url = try Bookmark.validatedURL(rawHREF)
            } catch {
                skipped += 1
                errors.append("Bookmark \(position): invalid URL “\(rawHREF)”.")
                continue
            }

            let tags = Bookmark.normalizeTags(record.tags)

            if let existing = try await Bookmark.query(on: db)
                .filter(\.$user.$id == userID)
                .filter(\.$url == url)
                .first()
            {
                existing.title = record.title
                existing.description = record.description
                existing.applyTags(tags)
                try await existing.save(on: db)
                updated += 1
            } else {
                let bookmark = Bookmark(
                    userID: userID, url: url, title: record.title, description: record.description, tags: tags
                )
                try await bookmark.save(on: db)
                if let created = record.createdAt {
                    bookmark.createdAt = created
                    try await bookmark.save(on: db)
                }
                imported += 1
            }
        }

        if imported > 0, let user = try await User.find(userID, on: db) {
            user.bookmarkCount += imported
            try await user.save(on: db)
        }

        return ImportResult(imported: imported, updated: updated, skipped: skipped, errors: errors)
    }
}
