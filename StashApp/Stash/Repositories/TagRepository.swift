// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import StashKit

/// Provides access to the current user's tags, derived from the local bookmark store.
///
/// Tags are computed by counting each tag across the locally stored bookmarks (the same aggregation
/// the backend's `/tags` endpoint performs) and cached for synchronous, local autocomplete. `load()`
/// derives once; `reload()` recomputes (pull-to-refresh); `refresh()` recomputes after a bookmark
/// mutation, leaving the current tags visible until the new set is ready, so observing views (notably
/// the always-mounted macOS sidebar) never flash empty. `reset()` clears the cache on sign-out so the
/// next user never sees the previous user's tags.
@MainActor
@Observable
final class TagRepository: TagAutocompleting {

    // MARK: Properties

    private(set) var tags: [Tag] = []

    /// The hierarchical tag tree shown in the sidebars, derived from `tags`. Cached here and rebuilt
    /// only when `tags` changes, so observing view bodies never rebuild the tree on every redraw.
    private(set) var tagHierarchy: [TagNode] = []

    /// The depth-tagged, flattened form of `tagHierarchy` consumed by the always-visible sidebars.
    /// Cached for the same reason as `tagHierarchy`: so a sidebar body re-evaluation (e.g. every
    /// selection tap) reads it instead of re-walking the tree.
    private(set) var flattenedTagHierarchy: [FlatTagNode] = []

    private let localStore: LocalStore
    private var hasLoaded = false

    // MARK: Lifecycle

    init(localStore: LocalStore) {
        self.localStore = localStore
    }

    // MARK: Functions

    func load() async throws {
        guard !hasLoaded else {
            return
        }

        derive()
    }

    func reload() async throws {
        derive()
    }

    func refresh() {
        derive()
    }

    func reset() {
        hasLoaded = false
        tags = []
        tagHierarchy = []
        flattenedTagHierarchy = []
        SharedTagCache.clear()
    }

    /// Returns cached tags matching the given prefix (case-insensitive, per-segment). Synchronous
    /// and local; it never performs a request.
    func autocompleteTags(prefix: String) -> [Tag] {
        tags.autocomplete(prefix: prefix)
    }

    private func derive() {
        var counts: [String: Int] = [:]
        var totals: [String: Int] = [:]
        for bookmark in localStore.fetchActive() {
            for tag in bookmark.tags {
                totals[tag, default: 0] += 1

                if !bookmark.isArchived {
                    counts[tag, default: 0] += 1
                }
            }
        }

        tags = totals
            .map { Tag(name: $0.key, count: counts[$0.key] ?? 0, totalCount: $0.value) }
            .sorted { $0.name < $1.name }
        tagHierarchy = tags.hierarchy()
        flattenedTagHierarchy = tagHierarchy.flattened()
        hasLoaded = true
        SharedTagCache.write(tags)
    }
}
