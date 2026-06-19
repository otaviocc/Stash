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

/// Provides access to the current user's bookmarks, reading from the local SwiftData store.
///
/// Reads come entirely from `LocalStore` — the query, search, tag, recency, and Smart View filters all
/// run in memory against the local copy, so browsing works offline. Writes are optimistic: each
/// create/update/delete applies to the local store and returns immediately (so the UI updates
/// instantly, online or off), then triggers a background `SyncEngine` cycle that pushes the queued
/// change and reconciles this list with the server's authoritative result. The local store is
/// populated by the sync engine's first full pull; this repository never fetches the list itself.
/// Each visible list owns its own instance so their pagination windows stay independent.
@MainActor
@Observable
final class BookmarkRepository: BookmarkCreating {

    // MARK: Nested Types

    /// What the current list shows: a filtered query, or a Smart View's saved rules evaluated locally.
    private enum Source: Equatable {

        case query(BookmarkQuery)
        case smartView(SmartView)
    }

    // MARK: Static Properties

    private static let perPage = 20

    // MARK: Properties

    private(set) var bookmarks: [Bookmark] = []
    private(set) var isLoading = false
    private(set) var hasMore = false

    private let clientProvider: StashClientProvider
    private let session: SessionRefreshing
    private let localStore: LocalStore
    private let syncEngine: SyncEngine
    private var source: Source = .query(BookmarkQuery())
    private var filtered: [Bookmark] = []
    private var shownCount = 0

    // MARK: Lifecycle

    init(
        clientProvider: StashClientProvider,
        session: SessionRefreshing,
        localStore: LocalStore,
        syncEngine: SyncEngine
    ) {
        self.clientProvider = clientProvider
        self.session = session
        self.localStore = localStore
        self.syncEngine = syncEngine
    }

    // MARK: Functions

    func load(query: BookmarkQuery) async throws {
        source = .query(query)
        loadFirstPage()
    }

    func load(smartView: SmartView) async throws {
        source = .smartView(smartView)
        loadFirstPage()
    }

    func loadNextPage() async throws {
        guard hasMore, !isLoading else {
            return
        }

        shownCount = min(shownCount + Self.perPage, filtered.count)
        publish()
    }

    /// Re-reads the store into the current visible window, preserving the pagination depth. Used to
    /// reflect a sync that ran outside this repository (the Settings "Sync Now", a reconnect, or a
    /// background refresh), which clears pending flags and applies server data the list still shows.
    func refresh() {
        refreshVisible()
    }

    func create(_ input: CreateBookmarkInput) async throws -> Bookmark {
        let bookmark = try queueCreate(input)
        scheduleSync()

        return bookmark
    }

    func update(
        id: UUID,
        title: String?,
        description: String?,
        tags: [String]
    ) async throws -> Bookmark {
        let bookmark = try queueUpdate(id: id, title: title, description: description, tags: tags)
        scheduleSync()

        return bookmark
    }

    func setArchived(id: UUID, archived: Bool) async throws -> Bookmark {
        let bookmark = try queueArchived(id: id, archived: archived)
        scheduleSync()

        return bookmark
    }

    func delete(id: UUID) async throws {
        queueDelete(id: id)
        scheduleSync()
    }

    func fetchMetadata(for url: URL) async -> PageMetadata {
        await ClientMetadataFetcher.fetch(for: url)
    }

    // MARK: - Reads

    private func loadFirstPage() {
        isLoading = true
        defer { isLoading = false }

        recomputeFiltered()
        shownCount = min(Self.perPage, filtered.count)
        publish()
    }

    private func refreshVisible() {
        recomputeFiltered()
        shownCount = min(max(shownCount, Self.perPage), filtered.count)
        publish()
    }

    private func recomputeFiltered() {
        let boundaries = BookmarkFilter.dateBoundaries()
        let active = localStore.fetchActive().compactMap(Bookmark.init(local:))

        let matched: [Bookmark] = switch source {
        case let .query(query):
            active.filter { BookmarkFilter.matches($0, query: query, boundaries: boundaries) }
        case let .smartView(smartView):
            active.filter { BookmarkFilter.matches($0, smartView: smartView, boundaries: boundaries) }
        }

        filtered = matched.sorted(by: BookmarkFilter.newestFirst)
    }

    private func publish() {
        bookmarks = Array(filtered.prefix(shownCount))
        hasMore = shownCount < filtered.count
    }

    // MARK: - Writes

    /// Pushes the queued change in the background and refreshes this list when it finishes, so the
    /// optimistic local row is reconciled with the server's authoritative result (real ID, normalized
    /// tags, fetched metadata) without blocking the caller on the network. Uses the push-only path —
    /// a write has nothing to pull, so a full sync here would be a wasted round-trip.
    private func scheduleSync() {
        Task {
            await syncEngine.pushPending()
            refreshVisible()
        }
    }

    private func queueCreate(_ input: CreateBookmarkInput) throws -> Bookmark {
        let record = LocalBookmark(localCreate: input, now: Date(), userID: clientProvider.currentUserID() ?? "")
        localStore.insert(record)
        localStore.save()
        refreshVisible()

        return try domainBookmark(from: record)
    }

    private func queueUpdate(
        id: UUID,
        title: String?,
        description: String?,
        tags: [String]
    ) throws -> Bookmark {
        guard let record = localStore.record(forServerID: id) else {
            throw AppError.unexpectedResponse
        }

        if let title { record.title = title }

        record.bookmarkDescription = description
        record.tags = tags
        markPending(record)

        return try domainBookmark(from: record)
    }

    private func queueArchived(id: UUID, archived: Bool) throws -> Bookmark {
        guard let record = localStore.record(forServerID: id) else {
            throw AppError.unexpectedResponse
        }

        record.isArchived = archived
        markPending(record)

        return try domainBookmark(from: record)
    }

    private func domainBookmark(from record: LocalBookmark) throws -> Bookmark {
        guard let bookmark = Bookmark(local: record) else {
            throw AppError.unexpectedResponse
        }

        return bookmark
    }

    private func queueDelete(id: UUID) {
        guard let record = localStore.record(forServerID: id) else {
            return
        }

        let now = Date()
        record.locallyDeletedAt = now
        record.pendingSyncAt = now
        record.syncError = nil
        localStore.save()
        refreshVisible()
    }

    private func markPending(_ record: LocalBookmark) {
        let now = Date()
        record.serverUpdatedAt = now
        record.pendingSyncAt = now
        record.syncError = nil
        localStore.save()
        refreshVisible()
    }
}
