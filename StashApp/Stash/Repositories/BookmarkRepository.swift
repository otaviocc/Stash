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

/// Provides access to the current user's bookmarks, reading from the local SwiftData store.
///
/// Reads come entirely from `LocalStore` — the query, search, tag, recency, and Smart View filters all
/// run in memory against the local copy, so browsing works offline. Writes are write-through: each
/// create/update/delete calls the API first (the server stays authoritative) and then mirrors the
/// result into the local store. The local store is populated by the one-time full fetch in
/// `AppEnvironment`; this repository never fetches the list itself. Each visible list owns its own
/// instance so their pagination windows stay independent.
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
    private var source: Source = .query(BookmarkQuery())
    private var filtered: [Bookmark] = []
    private var shownCount = 0

    // MARK: Lifecycle

    init(clientProvider: StashClientProvider, session: SessionRefreshing, localStore: LocalStore) {
        self.clientProvider = clientProvider
        self.session = session
        self.localStore = localStore
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

    func create(_ input: CreateBookmarkInput) async throws -> Bookmark {
        let client = try await authenticatedClient()
        let request = BookmarkRequestFactory.makeCreateRequest(
            CreateBookmarkRequest(
                url: input.url.absoluteString,
                title: input.title,
                description: input.description,
                tags: input.tags.isEmpty ? nil : input.tags,
                fetchMetadata: input.fetchMetadata
            )
        )
        let dto = try await client.run(request).value
        mirror(dto)

        return Bookmark(dto: dto)
    }

    func update(
        id: UUID,
        title: String?,
        description: String?,
        tags: [String]
    ) async throws -> Bookmark {
        let client = try await authenticatedClient()
        let request = BookmarkRequestFactory.makeUpdateRequest(
            id: id,
            body: UpdateBookmarkRequest(
                title: title,
                description: description,
                tags: tags
            )
        )
        let dto = try await client.run(request).value
        mirror(dto)

        return Bookmark(dto: dto)
    }

    func setArchived(id: UUID, archived: Bool) async throws -> Bookmark {
        let client = try await authenticatedClient()
        let request = BookmarkRequestFactory.makeUpdateRequest(
            id: id,
            body: UpdateBookmarkRequest(isArchived: archived)
        )
        let dto = try await client.run(request).value
        mirror(dto)

        return Bookmark(dto: dto)
    }

    func delete(id: UUID) async throws {
        let client = try await authenticatedClient()
        _ = try await client.run(BookmarkRequestFactory.makeDeleteRequest(id: id))
        localStore.remove(serverID: id)
        localStore.save()
        refreshVisible()
    }

    func fetchMetadata(for url: URL) async throws -> PageMetadata {
        let client = try await authenticatedClient()
        let dto = try await client.run(MetadataRequestFactory.makeFetchRequest(url: url)).value

        return PageMetadata(dto: dto)
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

    private func mirror(_ dto: BookmarkDTO) {
        localStore.upsert(dto)
        localStore.save()
        refreshVisible()
    }

    private func authenticatedClient() async throws -> StashClient {
        try await session.refreshIfNeeded()

        guard let client = clientProvider.client() else {
            throw AppError.notConfigured
        }

        return client
    }
}
