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

/// Provides access to the current user's tags with local caching.
///
/// Tags are fetched once via `load()` and cached in memory for synchronous, local autocomplete.
/// `reload()` forces a refetch (pull-to-refresh); `refresh()` does the same in the background after
/// a bookmark mutation, leaving the current tags visible until the new set arrives — so observing
/// views (notably the always-mounted macOS sidebar) never flash empty. `reset()` clears the cache on
/// sign-out so the next user never sees the previous user's tags.
@MainActor
@Observable
final class TagRepository: TagAutocompleting {

    // MARK: Properties

    private(set) var tags: [Tag] = []

    private let clientProvider: StashClientProvider
    private let session: SessionRefreshing
    private var hasLoaded = false

    // MARK: Lifecycle

    init(clientProvider: StashClientProvider, session: SessionRefreshing) {
        self.clientProvider = clientProvider
        self.session = session
    }

    // MARK: Functions

    func load() async throws {
        guard !hasLoaded else {
            return
        }

        try await performLoad()
    }

    func reload() async throws {
        try await performLoad()
    }

    func refresh() {
        Task { try? await reload() }
    }

    func reset() {
        hasLoaded = false
        tags = []
    }

    /// Returns cached tags matching the given prefix (case-insensitive, per-segment). Synchronous
    /// and local — it never performs a request.
    func autocompleteTags(prefix: String) -> [Tag] {
        tags.autocomplete(prefix: prefix)
    }

    private func performLoad() async throws {
        try await session.refreshIfNeeded()

        guard let client = clientProvider.client() else {
            throw AppError.notConfigured
        }

        let dtos = try await client.run(TagRequestFactory.makeListRequest()).value
        tags = dtos.map(Tag.init(dto:))
        hasLoaded = true
    }
}
