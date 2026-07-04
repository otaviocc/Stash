// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

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
