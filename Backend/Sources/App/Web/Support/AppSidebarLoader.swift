// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation

// MARK: - AppSidebarData

/// The sidebar portion of the bookmark-list page: the hierarchical tag tree plus the Views counts and
/// the user's Smart Views. Shared by the bookmark list and the Smart View results page so both render
/// the same sidebar.
struct AppSidebarData {

    let tags: [SidebarTag]
    let untaggedCount: Int
    let todayCount: Int
    let thisWeekCount: Int
    let smartViews: [SidebarSmartView]
}

// MARK: - AppSidebarLoader

/// Loads and assembles the `/app` sidebar for a user: aggregates per-tag visible/total counts and the
/// Untagged/Today/This Week counts from the user's bookmarks, builds the hierarchical tree via
/// `TagPresenter`, and lists the user's Smart Views. The single source for the sidebar so the bookmark
/// list and the Smart View results page can't drift.
enum AppSidebarLoader {

    static func load(
        for user: User,
        activeTag: String,
        activeSmartViewID: String,
        today: Date,
        week: Date,
        on db: any Database
    ) async throws -> AppSidebarData {
        let bookmarks = try await Bookmark.query(on: db)
            .filter(\.$user.$id == user.requireID())
            .all()
        let (counts, totalCounts) = Bookmark.tagCounts(in: bookmarks)
        var untaggedCount = 0
        var todayCount = 0
        var thisWeekCount = 0
        for bookmark in bookmarks {
            if bookmark.tags.isEmpty {
                untaggedCount += 1
            }

            if let created = bookmark.createdAt {
                if created >= today {
                    todayCount += 1
                }

                if created >= week {
                    thisWeekCount += 1
                }
            }
        }

        let views = try await SmartView.query(on: db)
            .filter(\.$user.$id == user.requireID())
            .sort(\.$name)
            .all()
        let smartViews = try views.map { view in
            let id = try view.requireID().uuidString
            return SidebarSmartView(name: view.name, href: "/app/smart-views/\(id)", isActive: id == activeSmartViewID)
        }

        return AppSidebarData(
            tags: TagPresenter.buildSidebar(counts: counts, totalCounts: totalCounts, activeTag: activeTag),
            untaggedCount: untaggedCount,
            todayCount: todayCount,
            thisWeekCount: thisWeekCount,
            smartViews: smartViews
        )
    }
}
