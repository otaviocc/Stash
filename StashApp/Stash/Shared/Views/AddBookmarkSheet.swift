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

import SwiftUI

/// Presents the shared `AddBookmarkView` as a sheet in the main app.
///
/// The URL is editable here (the user types or pastes it) and metadata is fetched on demand. A
/// saved bookmark invalidates the tag cache and dismisses the sheet; it also lands in the presenting
/// list because the shared `AddBookmarkView` writes through the list's repository.
struct AddBookmarkSheet: View {

    // MARK: SwiftUI Properties

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    // MARK: Properties

    /// The list's repository, so a saved bookmark appears in the list that presented this sheet.
    let repository: BookmarkRepository

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        AddBookmarkView(
            isURLEditable: true,
            autoFetchOnAppear: false,
            bookmarkStore: repository,
            tagStore: environment.tagRepository,
            onSaved: { _ in
                environment.tagRepository.invalidateCache()
                dismiss()
            },
            onCancel: { dismiss() }
        )
    }
}
