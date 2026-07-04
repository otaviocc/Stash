// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

// MARK: - TagTreeLabel

/// A single hierarchical tag-tree row: the node's own path component plus its bookmark count.
/// The count is hidden for synthetic parents (no count), matching the web sidebar.
///
/// The sidebars set `showsCountBadge` to render a `TagCountBadge` (which splits to surface archived
/// items); the tag picker leaves it off, showing the active count as plain text since archival state
/// is irrelevant when selecting tags.
struct TagTreeLabel: View {

    // MARK: Static Properties

    /// Leading inset added per nesting level, conveying tag hierarchy by indentation (mirroring the
    /// always-expanded web sidebar's per-depth padding).
    private static let indentPerLevel: CGFloat = 16

    // MARK: Properties

    let node: TagNode
    var depth = 0
    var showsCountBadge = false

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        HStack {
            Text(node.label)
            Spacer()
            makeCount()
        }
        .padding(.leading, CGFloat(depth) * Self.indentPerLevel)
    }

    // MARK: Content Methods

    @ViewBuilder
    private func makeCount() -> some View {
        if let count = node.count {
            if showsCountBadge {
                TagCountBadge(count: count, totalCount: node.totalCount ?? count)
            } else {
                Text("\(count)")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#if DEBUG
    #Preview {
        List {
            TagTreeLabel(node: TagNode(slug: "swift", label: "swift", count: 5, children: nil))
            TagTreeLabel(
                node: TagNode(slug: "swift", label: "swift", count: 5, totalCount: 5, children: nil),
                showsCountBadge: true
            )
            TagTreeLabel(
                node: TagNode(slug: "ios", label: "ios", count: 1, totalCount: 5, children: nil),
                showsCountBadge: true
            )
            TagTreeLabel(node: TagNode(slug: "swift/vapor", label: "vapor", count: nil, children: nil))
        }
    }
#endif
