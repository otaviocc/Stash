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

/// Provides access to the current user's Smart Views with local caching.
///
/// Smart Views are fetched once via `load()` and cached for the sidebars. `reload()` forces a refetch
/// (pull-to-refresh); `reset()` clears the cache on sign-out so the next user never sees the previous
/// user's Smart Views. Mirrors `TagRepository`: Smart Views are a small, per-user list browsed from the
/// sidebar, not a per-list paginated query (that is the bookmark results endpoint).
@MainActor
@Observable
final class SmartViewRepository {

    // MARK: Properties

    private(set) var smartViews: [SmartView] = []

    private let session: SessionRefreshing
    private var hasLoaded = false

    // MARK: Lifecycle

    init(session: SessionRefreshing) {
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

    func reset() {
        hasLoaded = false
        smartViews = []
    }

    func create(
        name: String,
        matchMode: String,
        conditions: [SmartViewCondition]
    ) async throws -> SmartView {
        let client = try await session.authorizedClient()
        let request = SmartViewRequestFactory.makeCreateRequest(
            SmartViewRequest(
                name: name,
                conditions: conditions.map(\.dto),
                matchMode: matchMode
            )
        )
        let smartView = try await SmartView(dto: client.run(request).value)
        smartViews.removeAll { $0.id == smartView.id }
        smartViews.append(smartView)
        sortByName()

        return smartView
    }

    func update(
        id: UUID,
        name: String,
        matchMode: String,
        conditions: [SmartViewCondition]
    ) async throws -> SmartView {
        let client = try await session.authorizedClient()
        let request = SmartViewRequestFactory.makeUpdateRequest(
            id: id,
            body: SmartViewRequest(
                name: name,
                conditions: conditions.map(\.dto),
                matchMode: matchMode
            )
        )
        let smartView = try await SmartView(dto: client.run(request).value)

        if let index = smartViews.firstIndex(where: { $0.id == id }) {
            smartViews[index] = smartView
        } else {
            smartViews.append(smartView)
        }

        sortByName()

        return smartView
    }

    func delete(id: UUID) async throws {
        let client = try await session.authorizedClient()
        _ = try await client.run(SmartViewRequestFactory.makeDeleteRequest(id: id))
        smartViews.removeAll { $0.id == id }
    }

    private func sortByName() {
        smartViews.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func performLoad() async throws {
        let client = try await session.authorizedClient()
        let dtos = try await client.run(SmartViewRequestFactory.makeListRequest()).value
        smartViews = dtos.map(SmartView.init(dto:))
        hasLoaded = true
    }
}
