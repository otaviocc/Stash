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

/// A read-only bookmark detail. Edit and delete arrive in a later session.
struct BookmarkDetailView: View {

    // MARK: Properties

    let bookmark: Bookmark

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    FaviconView(url: bookmark.url)
                    Text(bookmark.title)
                        .font(.headline)
                }

                Link(destination: bookmark.url) {
                    Text(bookmark.url.absoluteString)
                        .lineLimit(3)
                }
            }

            if let description = bookmark.description, !description.isEmpty {
                Section("Description") {
                    Text(description)
                }
            }

            if !bookmark.tags.isEmpty {
                Section("Tags") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(bookmark.tags, id: \.self) { tag in
                                TagPill(name: tag)
                            }
                        }
                    }
                }
            }

            Section {
                Link(destination: bookmark.url) {
                    Label("Open in Safari", systemImage: "safari")
                }
            }
        }
        .navigationTitle("Bookmark")
        .navigationBarTitleDisplayMode(.inline)
    }
}
