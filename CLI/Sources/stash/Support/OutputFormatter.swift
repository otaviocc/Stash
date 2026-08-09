// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import StashKit

// MARK: - OutputFormatter

/// Renders command output as pretty-printed JSON or as simple aligned text tables.
///
/// Tables are built with plain string padding (no external table library), matching the column
/// widths described in the CLI spec (ID truncated to 8, title to 40, URL to 50).
enum OutputFormatter {

    static func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(value)

        return String(bytes: data, encoding: .utf8) ?? ""
    }

    static func bookmarksTable(_ bookmarks: [BookmarkDTO]) -> String {
        guard !bookmarks.isEmpty else {
            return "No bookmarks found."
        }

        let idWidth = 8
        let titleWidth = 40
        let urlWidth = 50

        var rows = [
            row(
                "ID".padded(to: idWidth),
                "TITLE".padded(to: titleWidth),
                "URL".padded(to: urlWidth),
                "TAGS"
            )
        ]

        for bookmark in bookmarks {
            let id = String(bookmark.id.uuidString.prefix(8))
            let title = bookmark.title.truncated(to: titleWidth)
            let url = bookmark.url.absoluteString.truncated(to: urlWidth)
            let tags = bookmark.tags.joined(separator: ", ")
            rows.append(
                row(
                    id.padded(to: idWidth),
                    title.padded(to: titleWidth),
                    url.padded(to: urlWidth),
                    tags
                )
            )
        }

        return rows.joined(separator: "\n")
    }

    static func bookmarkDetail(_ bookmark: BookmarkDTO) -> String {
        var lines = [
            "ID:          \(bookmark.id.uuidString)",
            "URL:         \(bookmark.url.absoluteString)",
            "Title:       \(bookmark.title)"
        ]

        if let description = bookmark.description, !description.isEmpty {
            lines.append("Description: \(description)")
        }

        lines.append("Tags:        \(bookmark.tags.isEmpty ? "—" : bookmark.tags.joined(separator: ", "))")
        lines.append("Archived:    \(bookmark.isArchived ? "yes" : "no")")
        lines.append("Read later:  \(bookmark.isReadLater ? "yes" : "no")")
        lines.append("Created:     \(ISO8601DateFormatter().string(from: bookmark.createdAt))")

        return lines.joined(separator: "\n")
    }

    static func smartViewsTable(_ smartViews: [SmartViewDTO]) -> String {
        guard !smartViews.isEmpty else {
            return "No Smart Views found."
        }

        let nameWidth = 30
        let matchWidth = 5
        let conditionsWidth = 40

        var rows = [
            row(
                "NAME".padded(to: nameWidth),
                "MATCH".padded(to: matchWidth),
                "CONDITIONS".padded(to: conditionsWidth),
                "ID"
            )
        ]

        for smartView in smartViews {
            let name = smartView.name.truncated(to: nameWidth).padded(to: nameWidth)
            let match = smartView.matchMode.padded(to: matchWidth)
            let conditions = smartView.conditions
                .map { "\($0.type)=\($0.value)" }
                .joined(separator: ", ")
                .truncated(to: conditionsWidth)
                .padded(to: conditionsWidth)
            rows.append(
                row(
                    name,
                    match,
                    conditions,
                    smartView.id.uuidString
                )
            )
        }

        return rows.joined(separator: "\n")
    }

    static func usersTable(_ users: [UserDTO]) -> String {
        guard !users.isEmpty else {
            return "No users found."
        }

        var rows = [
            row(
                "USERNAME".padded(to: 20),
                "ROLE".padded(to: 6),
                "ACTIVE".padded(to: 7),
                "2FA".padded(to: 4),
                "BOOKMARKS".padded(to: 10),
                "ID"
            )
        ]

        for user in users {
            rows.append(
                row(
                    user.username.truncated(to: 20).padded(to: 20),
                    user.role.rawValue.padded(to: 6),
                    (user.isActive ? "yes" : "no").padded(to: 7),
                    (user.isTOTPEnabled ? "on" : "off").padded(to: 4),
                    String(user.bookmarkCount).padded(to: 10),
                    user.id.uuidString
                )
            )
        }

        return rows.joined(separator: "\n")
    }

    static func statsSummary(_ stats: AdminStatsDTO) -> String {
        var lines = [
            "Total users:     \(stats.totalUsers)",
            "Total bookmarks: \(stats.totalBookmarks)",
            ""
        ]

        lines.append(
            row(
                "USERNAME".padded(to: 20),
                "ACTIVE".padded(to: 7),
                "BOOKMARKS"
            )
        )

        for user in stats.users {
            lines.append(
                row(
                    user.username.truncated(to: 20).padded(to: 20),
                    (user.isActive ? "yes" : "no").padded(to: 7),
                    String(user.bookmarkCount)
                )
            )
        }

        return lines.joined(separator: "\n")
    }

    private static func row(_ columns: String...) -> String {
        columns.joined(separator: "  ")
    }
}

extension String {

    func padded(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }

    func truncated(to width: Int) -> String {
        guard count > width else {
            return self
        }

        let end = index(startIndex, offsetBy: width - 1)

        return String(self[..<end]) + "…"
    }
}
