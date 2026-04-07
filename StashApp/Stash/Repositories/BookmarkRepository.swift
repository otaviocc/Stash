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

/// Provides access to the current user's bookmarks.
///
/// Maps StashKit's `BookmarkDTO` to the local `Bookmark` model and tracks pagination state so the
/// list view can load further pages and pull to refresh. Every request is preceded by a silent
/// token refresh via the injected session.
@MainActor
@Observable
final class BookmarkRepository: BookmarkCreating {

    // MARK: Nested Types

    /// Where the current list of bookmarks comes from: a regular filtered query, or a Smart View's
    /// saved query run server-side. The source is stored so `loadNextPage()` re-fetches consistently.
    private enum Source: Equatable {

        case query(BookmarkQuery)
        case smartView(UUID)
    }

    // MARK: Static Properties

    private static let perPage = 20

    // MARK: Properties

    private(set) var bookmarks: [Bookmark] = []
    private(set) var isLoading = false
    private(set) var hasMore = false

    private let clientProvider: StashClientProvider
    private let session: SessionRefreshing
    private var source: Source = .query(BookmarkQuery())
    private var currentPage = 1
    private var total = 0

    // MARK: Computed Properties

    /// The archived state the current source displays — a query's own flag, or `false` for a Smart
    /// View (its results default to non-archived unless it carries an `isArchived` condition). Used to
    /// decide whether a freshly created or archived bookmark belongs in the visible list.
    private var displaysArchived: Bool {
        switch source {
        case let .query(query): query.archived
        case .smartView: false
        }
    }

    // MARK: Lifecycle

    init(clientProvider: StashClientProvider, session: SessionRefreshing) {
        self.clientProvider = clientProvider
        self.session = session
    }

    // MARK: Functions

    func load(query: BookmarkQuery) async throws {
        source = .query(query)

        try await loadFirstPage()
    }

    func load(smartViewID: UUID) async throws {
        source = .smartView(smartViewID)

        try await loadFirstPage()
    }

    func loadNextPage() async throws {
        guard hasMore, !isLoading else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        let nextPage = currentPage + 1
        let page = try await fetch(page: nextPage)
        currentPage = nextPage
        total = page.metadata.total
        bookmarks.append(contentsOf: page.items.map(Bookmark.init(dto:)))
        updateHasMore()
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
        let bookmark = Bookmark(dto: dto)

        if !bookmark.isArchived, displaysArchived == false {
            bookmarks.insert(bookmark, at: 0)
            total += 1
        }

        return bookmark
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
        let bookmark = try await Bookmark(dto: client.run(request).value)

        if let index = bookmarks.firstIndex(where: { $0.id == id }) {
            bookmarks[index] = bookmark
        }

        return bookmark
    }

    func setArchived(id: UUID, archived: Bool) async throws -> Bookmark {
        let client = try await authenticatedClient()
        let request = BookmarkRequestFactory.makeUpdateRequest(
            id: id,
            body: UpdateBookmarkRequest(isArchived: archived)
        )
        let bookmark = try await Bookmark(dto: client.run(request).value)

        if bookmark.isArchived == displaysArchived {
            if let index = bookmarks.firstIndex(where: { $0.id == id }) {
                bookmarks[index] = bookmark
            }
        } else if let index = bookmarks.firstIndex(where: { $0.id == id }) {
            bookmarks.remove(at: index)
            total = max(0, total - 1)
            updateHasMore()
        }

        return bookmark
    }

    func delete(id: UUID) async throws {
        let client = try await authenticatedClient()
        _ = try await client.run(BookmarkRequestFactory.makeDeleteRequest(id: id))

        if let index = bookmarks.firstIndex(where: { $0.id == id }) {
            bookmarks.remove(at: index)
            total = max(0, total - 1)
            updateHasMore()
        }
    }

    func fetchMetadata(for url: URL) async throws -> PageMetadata {
        let client = try await authenticatedClient()
        let dto = try await client.run(MetadataRequestFactory.makeFetchRequest(url: url)).value

        return PageMetadata(dto: dto)
    }

    private func loadFirstPage() async throws {
        currentPage = 1

        isLoading = true
        defer { isLoading = false }

        let page = try await fetch(page: 1)
        total = page.metadata.total
        bookmarks = page.items.map(Bookmark.init(dto:))
        updateHasMore()
    }

    private func fetch(page: Int) async throws -> BookmarkPageDTO {
        let client = try await authenticatedClient()

        switch source {
        case let .query(query):
            let listQuery = BookmarkListQuery(
                searchQuery: query.searchQuery,
                tag: query.tag,
                archived: query.archived,
                page: page,
                perPage: Self.perPage
            )

            return try await client.run(BookmarkRequestFactory.makeListRequest(query: listQuery)).value

        case let .smartView(id):
            let request = SmartViewRequestFactory.makeBookmarksRequest(
                id: id,
                page: page,
                perPage: Self.perPage
            )

            return try await client.run(request).value
        }
    }

    private func authenticatedClient() async throws -> StashClient {
        try await session.refreshIfNeeded()

        guard let client = clientProvider.client() else {
            throw AppError.notConfigured
        }

        return client
    }

    private func updateHasMore() {
        hasMore = bookmarks.count < total
    }
}
