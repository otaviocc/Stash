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

/// The Share Extension's tag store: load once, then offer local prefix autocomplete.
///
/// A smaller counterpart to the app's `TagRepository` with no cache-invalidation surface — the
/// extension is short-lived, so the tag list is loaded once per invocation. It is `@Observable` so
/// the shared `AddBookmarkView` re-renders its suggestion chips when the list arrives, and conforms
/// to `TagAutocompleting`.
@MainActor
@Observable
final class ExtensionTagRepository: TagAutocompleting {

    // MARK: Properties

    private(set) var tags: [Tag] = []

    private let session: ExtensionSession
    private var hasLoaded = false

    // MARK: Lifecycle

    init(session: ExtensionSession) {
        self.session = session
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
        let needle = prefix.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else {
            return []
        }

        return tags.filter { $0.name.lowercased().hasPrefix(needle) }
    }
}
