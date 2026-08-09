// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

/// Message strings for the `info`-level activity log lines shown on `/admin/logs`
/// (Docs/product-web.md §12). Centralized here so the API and web surfaces, which each save
/// bookmarks, Smart Views, etc. independently, with no shared controller, log identical wording,
/// and so the phrasing is unit-testable without needing a live `RingBufferLogHandler` (which is
/// only wired up in `entrypoint.main`, not in the test harness).
enum ActivityLog {

    // MARK: User-attributed events

    static func bookmarkSaved(url: String, user: String) -> String {
        "Bookmark saved: \(url) (user \(user))"
    }

    static func bookmarkDeleted(url: String, user: String) -> String {
        "Bookmark deleted: \(url) (user \(user))"
    }

    static func allBookmarksDeleted(count: Int, user: String) -> String {
        "All bookmarks deleted: \(count) removed (user \(user))"
    }

    static func smartViewCreated(name: String, user: String) -> String {
        "Smart View created: \"\(name)\" (user \(user))"
    }

    static func smartViewUpdated(name: String, user: String) -> String {
        "Smart View updated: \"\(name)\" (user \(user))"
    }

    static func smartViewDeleted(name: String, user: String) -> String {
        "Smart View deleted: \"\(name)\" (user \(user))"
    }

    // MARK: Shared services / background workers (no user in scope)

    static func tagRenamed(from: String, to: String, affected: Int) -> String {
        "Tag renamed: \(from) -> \(to) (\(affected) bookmarks)"
    }

    static func tagDeleted(tag: String, affected: Int) -> String {
        "Tag deleted: \(tag) (\(affected) bookmarks)"
    }

    static func faviconCached(domain: String) -> String {
        "Favicon cached for \(domain)"
    }

    static func faviconFailed(domain: String) -> String {
        "Favicon caching failed for \(domain)"
    }

    static func waybackArchived(url: String) -> String {
        "Wayback snapshot saved for \(url)"
    }
}
