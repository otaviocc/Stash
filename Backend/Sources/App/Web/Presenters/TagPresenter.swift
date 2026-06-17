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

import Foundation

/// Pure presentation helpers for tags in the user-facing web frontend: hierarchical display,
/// sidebar-tree building, tag-filter URL building, and free-text tag-input parsing. No request or
/// database access — the web controllers load the data and call these to shape it for Leaf.
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

    static func parseTags(_ raw: String) -> [String] {
        raw.components(separatedBy: CharacterSet(charactersIn: ",").union(.whitespacesAndNewlines))
    }

    static func jsonArray(_ strings: [String]) -> String {
        guard let data = try? JSONEncoder().encode(strings),
              let json = String(data: data, encoding: .utf8) else { return "[]" }

        return json
    }
}
