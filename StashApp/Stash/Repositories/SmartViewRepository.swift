// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import StashKit

/// Provides access to the current user's Smart Views with local caching, backed by the on-disk
/// `LocalStore` so the list survives a cold launch offline.
///
/// `load()` first reads the cached definitions straight from `LocalStore` — synchronous in effect and
/// available with no network at all — then makes a best-effort attempt to refresh from the server and
/// reconcile the cache; a failed refresh is silently ignored as long as there was something cached to
/// show, and only propagates if the cache was empty too (e.g. the very first launch, offline). `reload()`
/// always refreshes from the server and always throws on failure (pull-to-refresh, and the Smart View
/// management screen, which should surface a real error). `reset()` clears the in-memory cache on
/// sign-out; the on-disk cache's own wipe policy lives in `LocalStore.wipe`/`wipeAll`. Mirrors
/// `TagRepository`: Smart Views are a small, per-user list browsed from the sidebar, not a per-list
/// paginated query (that is the bookmark results endpoint, which the native apps never call — Smart
/// View results are evaluated locally by `BookmarkFilter`).
///
/// Smart Views are never authored offline: `create`/`update`/`delete` always call the server directly,
/// with no local write queue, and fail outright (surfaced as a user-visible error) when offline. On
/// success, the on-disk cache is patched immediately alongside the in-memory array, so an authored
/// change is available offline right away rather than waiting for the next full refresh.
@MainActor
@Observable
final class SmartViewRepository {

    // MARK: Properties

    private(set) var smartViews: [SmartView] = []

    private let session: SessionRefreshing
    private let localStore: LocalStore
    private let clientProvider: StashClientProvider
    private var hasLoaded = false

    // MARK: Computed Properties

    private var currentUserID: String {
        clientProvider.currentUserID() ?? ""
    }

    // MARK: Lifecycle

    init(
        session: SessionRefreshing,
        localStore: LocalStore,
        clientProvider: StashClientProvider
    ) {
        self.session = session
        self.localStore = localStore
        self.clientProvider = clientProvider
    }

    // MARK: Functions

    func load() async throws {
        guard !hasLoaded else {
            return
        }

        loadFromDisk()
        hasLoaded = true

        do {
            try await performLoad()
        } catch {
            guard smartViews.isEmpty else {
                return
            }

            throw error
        }
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
        let dto = try await client.run(request).value
        let smartView = SmartView(dto: dto)
        smartViews.removeAll { $0.id == smartView.id }
        smartViews.append(smartView)
        sortByName()
        localStore.upsertSmartView(dto, userID: currentUserID)

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
        let dto = try await client.run(request).value
        let smartView = SmartView(dto: dto)

        if let index = smartViews.firstIndex(where: { $0.id == id }) {
            smartViews[index] = smartView
        } else {
            smartViews.append(smartView)
        }

        sortByName()
        localStore.upsertSmartView(dto, userID: currentUserID)

        return smartView
    }

    func delete(id: UUID) async throws {
        let client = try await session.authorizedClient()
        _ = try await client.run(SmartViewRequestFactory.makeDeleteRequest(id: id))
        smartViews.removeAll { $0.id == id }
        localStore.deleteSmartView(id: id)
    }

    private func sortByName() {
        smartViews.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Populates `smartViews` synchronously from the on-disk cache. Works fully offline; the cache is
    /// empty only before the very first successful `performLoad()` ever runs on this device.
    private func loadFromDisk() {
        smartViews = localStore.fetchSmartViews(userID: currentUserID).map(SmartView.init(local:))
    }

    private func performLoad() async throws {
        let client = try await session.authorizedClient()
        let dtos = try await client.run(SmartViewRequestFactory.makeListRequest()).value
        let userID = currentUserID
        localStore.replaceSmartViews(dtos, userID: userID)
        smartViews = dtos.map(SmartView.init(dto:))
        sortByName()
    }
}
