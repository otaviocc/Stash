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

/// The Share Extension's bookmark store: create, fetch metadata, delete.
///
/// A deliberately smaller counterpart to the app's `BookmarkRepository` — it carries no list or
/// pagination state because the extension only ever saves one bookmark (and may undo it). It
/// conforms to `BookmarkCreating` so the shared `AddBookmarkView` can drive it.
@MainActor
final class ExtensionBookmarkRepository: BookmarkCreating {

    // MARK: Properties

    private let session: ExtensionSession

    // MARK: Lifecycle

    init(session: ExtensionSession) {
        self.session = session
    }

    // MARK: Functions

    func create(_ input: CreateBookmarkInput) async throws -> Bookmark {
        let client = try await session.authenticatedClient()
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

        return Bookmark(dto: dto)
    }

    func fetchMetadata(for url: URL) async throws -> PageMetadata {
        let client = try await session.authenticatedClient()
        let dto = try await client.run(MetadataRequestFactory.makeFetchRequest(url: url)).value

        return PageMetadata(dto: dto)
    }

    func deleteBookmark(id: UUID) async throws {
        let client = try await session.authenticatedClient()
        _ = try await client.run(BookmarkRequestFactory.makeDeleteRequest(id: id))
    }
}
