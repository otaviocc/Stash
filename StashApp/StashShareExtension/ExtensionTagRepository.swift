// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import StashKit

/// The Share Extension's tag store: seed from the app's shared snapshot, then best-effort refresh
/// from the network.
///
/// A smaller counterpart to the app's `TagRepository` with no cache-invalidation surface — the
/// extension is short-lived, so the tag list is loaded once per invocation. Because the extension
/// cannot open the app's private SwiftData store, it seeds `tags` from `SharedTagCache` (written by
/// the app on every derive) so the tag picker works even when the backend is unreachable, then tries
/// a network refresh for the freshest list, keeping the seeded snapshot if that fails. It is
/// `@Observable` so the shared `AddBookmarkView` re-renders its suggestion chips when the list
/// changes, and conforms to `TagAutocompleting`.
@MainActor
@Observable
final class ExtensionTagRepository: TagAutocompleting {

    // MARK: Properties

    private(set) var tags: [Tag]

    private let session: ExtensionSession
    private var hasLoaded = false

    // MARK: Computed Properties

    /// Derived on access rather than cached: the extension is short-lived and the tag list is small,
    /// so there is no observing-view redraw cost worth caching against (unlike the app's repository).
    var tagHierarchy: [TagNode] {
        tags.hierarchy()
    }

    // MARK: Lifecycle

    init(session: ExtensionSession) {
        self.session = session
        tags = SharedTagCache.read()
    }

    // MARK: Functions

    func load() async throws {
        guard !hasLoaded else {
            return
        }

        let client = try await session.authenticatedClient()
        let dtos = try await client.run(TagRequestFactory.makeListRequest()).value
        tags = dtos.map(Tag.init(dto:))
        hasLoaded = true
    }

    func autocompleteTags(prefix: String) -> [Tag] {
        tags.autocomplete(prefix: prefix)
    }
}
