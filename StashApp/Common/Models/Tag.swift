// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import StashKit

// MARK: - Tag

/// A tag with its usage counts: `count` is the active (non-archived) bookmarks carrying the tag,
/// `totalCount` includes archived ones. Both are derived locally from the SwiftData store; the
/// backend `/tags` endpoint returns only the active count.
struct Tag: Identifiable, Hashable, Codable {

    // MARK: Properties

    let name: String
    let count: Int
    let totalCount: Int

    // MARK: Computed Properties

    var id: String {
        name
    }
}

// MARK: - Tag + DTO

extension Tag {

    init(
        dto: TagDTO
    ) {
        name = dto.name
        count = dto.count
        totalCount = dto.count
    }
}

// MARK: - TagNode

/// One node of the hierarchical tag tree shown in the sidebars. A `/`-delimited tag like
/// `swift/vapor` becomes a `swift` node with a `vapor` child; `label` is the node's own path
/// component, `slug` its full path (the value sent as the `tag` filter). `count` (active) and
/// `totalCount` (including archived) are both `nil` for synthetic parents that exist only to nest
/// their children, so no count is shown for them.
struct TagNode: Identifiable, Hashable {

    // MARK: Properties

    let slug: String
    let label: String
    let count: Int?
    let totalCount: Int?
    let children: [TagNode]?

    // MARK: Computed Properties

    var id: String {
        slug
    }

    // MARK: Lifecycle

    init(
        slug: String,
        label: String,
        count: Int?,
        totalCount: Int? = nil,
        children: [TagNode]?
    ) {
        self.slug = slug
        self.label = label
        self.count = count
        self.totalCount = totalCount
        self.children = children
    }
}

// MARK: - FlatTagNode

/// One row of the always-visible, indented tag tree: a tree node plus its nesting depth. The
/// native sidebars and picker render the tree flattened and indented (mirroring the always-expanded
/// web sidebar) rather than collapsed, so the whole list is visible without expanding nodes.
struct FlatTagNode: Identifiable, Hashable {

    // MARK: Properties

    let node: TagNode
    let depth: Int

    // MARK: Computed Properties

    var id: String {
        node.slug
    }
}

// MARK: - Tag normalization

extension String {

    // MARK: Computed Properties

    /// Renders a `/`-delimited tag slug as its ` › `-separated display form (`swift/vapor` →
    /// `swift › vapor`). The single place this hierarchy formatting lives, shared by the tag pills,
    /// the selected-tag chips, and the list's tag-filter empty state.
    var tagDisplayName: String {
        components(separatedBy: "/").joined(separator: " › ")
    }

    // MARK: Functions

    /// Normalizes a raw tag string the way the backend's `Bookmark.normalizeTagQuery` does: trim,
    /// lowercase, strip wrapping slashes, and drop pipes. The single place the native clients
    /// normalize a tag before sending it, so the tag picker's "Create" path and the offline filter
    /// stay in sync with the server.
    func normalizedTagQuery() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "|", with: "")
    }
}

// MARK: - Tag autocomplete

extension [Tag] {

    /// Returns tags whose name, or any `/`-delimited segment of it, begins with the given prefix,
    /// case-insensitively. Mirrors the web frontend's per-segment autocomplete, so typing `music`
    /// surfaces `music`, `kind/music-gear`, and `learning/music-theory`.
    func autocomplete(prefix: String) -> [Tag] {
        let needle = prefix.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else {
            return []
        }

        return filter { tag in
            tag.name
                .lowercased()
                .split(separator: "/", omittingEmptySubsequences: false)
                .contains { $0.hasPrefix(needle) }
        }
    }

    /// Builds the hierarchical tag tree shown in the sidebars, mirroring the web frontend's
    /// `buildSidebar`: every `/`-delimited ancestor becomes a node (synthetic parents that exist
    /// only to nest their children carry no count), children nest under their parent, and siblings
    /// are alphabetical at every level.
    func hierarchy() -> [TagNode] {
        let counts = Dictionary(map { ($0.name, $0.count) }) { lhs, _ in lhs }
        let totals = Dictionary(map { ($0.name, $0.totalCount) }) { lhs, _ in lhs }
        var children: [String: [String]] = [:]
        var seen = Set<String>()
        for tag in self {
            let parts = tag.name.split(separator: "/").map(String.init)
            guard !parts.isEmpty else { continue }

            for depth in 1...parts.count {
                let slug = parts[0..<depth].joined(separator: "/")
                guard seen.insert(slug).inserted else { continue }

                let parent = depth == 1 ? "" : parts[0..<(depth - 1)].joined(separator: "/")
                children[parent, default: []].append(slug)
            }
        }

        func build(_ parent: String) -> [TagNode] {
            (children[parent] ?? []).sorted().map { slug in
                let label = slug.split(separator: "/").last.map(String.init) ?? slug
                let kids = build(slug)
                return TagNode(
                    slug: slug,
                    label: label,
                    count: counts[slug],
                    totalCount: totals[slug],
                    children: kids.isEmpty ? nil : kids
                )
            }
        }

        return build("")
    }
}

// MARK: - Tag tree flattening

extension [TagNode] {

    /// Flattens the nested tag tree into a depth-tagged, pre-order sequence for the always-visible,
    /// indentation-based sidebar (mirroring the always-expanded web sidebar). Each parent precedes
    /// its children, and the sibling order produced by `hierarchy()` is preserved.
    func flattened() -> [FlatTagNode] {
        var result: [FlatTagNode] = []
        func append(_ nodes: [TagNode], depth: Int) {
            for node in nodes {
                result.append(FlatTagNode(node: node, depth: depth))
                if let children = node.children {
                    append(children, depth: depth + 1)
                }
            }
        }

        append(self, depth: 0)

        return result
    }
}
