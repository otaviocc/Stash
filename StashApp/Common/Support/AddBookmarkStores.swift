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

// MARK: - BookmarkCreating

/// A store that can create a bookmark and fetch page metadata.
///
/// The shared `AddBookmarkView` depends on this narrow protocol rather than a concrete repository,
/// so the same form serves the main app's `BookmarkRepository` and the Share Extension's
/// `ExtensionBookmarkRepository` without either knowing about the other.
@MainActor
protocol BookmarkCreating: AnyObject {

    func create(
        _ input: CreateBookmarkInput
    ) async throws -> Bookmark

    func fetchMetadata(
        for url: URL
    ) async throws -> PageMetadata
}

// MARK: - TagAutocompleting

/// A store that loads the user's tags and offers local prefix autocomplete.
///
/// Like `BookmarkCreating`, this lets the shared `AddBookmarkView` drive its tag suggestions from
/// either the app's `TagRepository` or the extension's `ExtensionTagRepository`.
@MainActor
protocol TagAutocompleting: AnyObject {

    // MARK: Computed Properties

    var tags: [Tag] { get }

    /// The hierarchical tag tree derived from `tags`, used by the tag picker. The app caches it on
    /// `TagRepository`; the extension derives it on the fly.
    var tagHierarchy: [TagNode] { get }

    // MARK: Functions

    func load() async throws

    func autocompleteTags(
        prefix: String
    ) -> [Tag]
}
