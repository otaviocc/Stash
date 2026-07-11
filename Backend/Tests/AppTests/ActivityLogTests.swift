// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Testing
@testable import App

/// Verifies the exact wording of the `info`-level activity log lines surfaced on `/admin/logs`
/// (PRD §12). Pure string tests: the ring buffer is only wired up in `entrypoint.main`, not the
/// test harness, so this is the seam where the phrasing (and API/web parity, since both surfaces
/// call the same helper) is actually testable.
@Suite("ActivityLog — message wording")
struct ActivityLogTests {

    @Test("bookmark saved")
    func bookmarkSaved() {
        #expect(
            ActivityLog.bookmarkSaved(url: "https://example.com", user: "otavio")
                == "Bookmark saved: https://example.com (user otavio)"
        )
    }

    @Test("bookmark deleted")
    func bookmarkDeleted() {
        #expect(
            ActivityLog.bookmarkDeleted(url: "https://example.com", user: "otavio")
                == "Bookmark deleted: https://example.com (user otavio)"
        )
    }

    @Test("all bookmarks deleted")
    func allBookmarksDeleted() {
        #expect(
            ActivityLog.allBookmarksDeleted(count: 42, user: "otavio")
                == "All bookmarks deleted: 42 removed (user otavio)"
        )
    }

    @Test("Smart View created")
    func smartViewCreated() {
        #expect(
            ActivityLog.smartViewCreated(name: "Unread", user: "otavio")
                == "Smart View created: \"Unread\" (user otavio)"
        )
    }

    @Test("Smart View updated")
    func smartViewUpdated() {
        #expect(
            ActivityLog.smartViewUpdated(name: "Unread", user: "otavio")
                == "Smart View updated: \"Unread\" (user otavio)"
        )
    }

    @Test("Smart View deleted")
    func smartViewDeleted() {
        #expect(
            ActivityLog.smartViewDeleted(name: "Unread", user: "otavio")
                == "Smart View deleted: \"Unread\" (user otavio)"
        )
    }

    @Test("tag renamed")
    func tagRenamed() {
        #expect(
            ActivityLog.tagRenamed(from: "swift", to: "swiftui", affected: 3)
                == "Tag renamed: swift -> swiftui (3 bookmarks)"
        )
    }

    @Test("tag deleted")
    func tagDeleted() {
        #expect(
            ActivityLog.tagDeleted(tag: "old", affected: 5)
                == "Tag deleted: old (5 bookmarks)"
        )
    }

    @Test("favicon cached")
    func faviconCached() {
        #expect(ActivityLog.faviconCached(domain: "example.com") == "Favicon cached for example.com")
    }

    @Test("favicon failed")
    func faviconFailed() {
        #expect(ActivityLog.faviconFailed(domain: "example.com") == "Favicon caching failed for example.com")
    }

    @Test("wayback archived")
    func waybackArchived() {
        #expect(
            ActivityLog.waybackArchived(url: "https://example.com") == "Wayback snapshot saved for https://example.com"
        )
    }
}
