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
import StashKit

// MARK: - Tag

/// A tag with its usage count.
struct Tag: Identifiable, Hashable {

    // MARK: Properties

    let name: String
    let count: Int

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
    }
}

// MARK: - TagNode

/// One node of the hierarchical tag tree shown in the sidebars. A `/`-delimited tag like
/// `swift/vapor` becomes a `swift` node with a `vapor` child; `label` is the node's own path
/// component, `slug` its full path (the value sent as the `tag` filter). `count` is `nil` for
/// synthetic parents that exist only to nest their children, so no count is shown for them.
struct TagNode: Identifiable, Hashable {

    // MARK: Properties

    let slug: String
    let label: String
    let count: Int?
    let children: [TagNode]?

    // MARK: Computed Properties

    var id: String {
        slug
    }
}

// MARK: - Tag normalization

extension String {

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

    /// Returns tags whose name — or any `/`-delimited segment of it — begins with the given prefix,
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
                    children: kids.isEmpty ? nil : kids
                )
            }
        }

        return build("")
    }
}
