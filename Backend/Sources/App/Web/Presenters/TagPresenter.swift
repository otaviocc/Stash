// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Pure presentation helpers for tags in the user-facing web frontend: hierarchical display,
/// sidebar-tree building, and tag-filter URL building. No request or database access; the web
/// controllers load the data and call these to shape it for Leaf.
enum TagPresenter {

    /// Builds the flat, pre-ordered hierarchical sidebar tag list. Synthetic parents (no direct count)
    /// are inserted so children always nest, and each entry carries a visible/hidden count split.
    static func buildSidebar(
        counts: [String: Int],
        totalCounts: [String: Int],
        activeTag: String
    ) -> [SidebarTag] {
        var slugs = Set<String>()
        for key in totalCounts.keys {
            let parts = key.split(separator: "/").map(String.init)
            guard !parts.isEmpty else { continue }

            for depth in 1...parts.count {
                slugs.insert(parts[0..<depth].joined(separator: "/"))
            }
        }
        let ordered = slugs.sorted { lhs, rhs in
            let a = lhs.split(separator: "/").map(String.init)
            let b = rhs.split(separator: "/").map(String.init)
            for i in 0..<min(a.count, b.count) where a[i] != b[i] {
                return a[i] < b[i]
            }
            return a.count < b.count
        }
        return ordered.map { slug in
            let comps = slug.split(separator: "/").map(String.init)
            let count = counts[slug] ?? 0
            let totalCount = totalCounts[slug] ?? 0
            return SidebarTag(
                label: comps.last ?? slug,
                href: tagHref(slug),
                count: count,
                totalCount: totalCount,
                hiddenCount: max(0, totalCount - count),
                depth: comps.count - 1,
                isActive: slug == activeTag
            )
        }
    }

    static func tagHref(_ slug: String) -> String {
        "/app?tag=\(queryValue(slug))"
    }

    static func queryValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "/?&=#+%")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// Renders a hierarchical tag (`swift/vapor`) as `swift › vapor` for display, mirroring the apps.
    static func display(_ tag: String) -> String {
        tag.components(separatedBy: "/").joined(separator: " › ")
    }

    static func jsonArray(_ strings: [String]) -> String {
        guard let data = try? JSONEncoder().encode(strings),
              let json = String(data: data, encoding: .utf8) else { return "[]" }

        return json
    }
}
