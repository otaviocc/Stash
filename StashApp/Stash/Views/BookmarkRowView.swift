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

// MARK: - BookmarkRowView

/// A single bookmark row: favicon, title, hostname, and tag pills.
struct BookmarkRowView: View {

    // MARK: Properties

    let bookmark: Bookmark

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                FaviconView(url: bookmark.url)
                Text(bookmark.title)
                    .font(.headline)
                    .lineLimit(2)
            }

            Text(bookmark.hostname)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !bookmark.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(bookmark.tags.prefix(3), id: \.self) { tag in
                        TagPill(name: tag)
                    }

                    if bookmark.tags.count > 3 {
                        Text("+\(bookmark.tags.count - 3)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - TagPill

/// A small capsule label for a tag.
struct TagPill: View {

    // MARK: Properties

    let name: String

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        Text(name)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.15), in: .capsule)
            .foregroundStyle(Color.accentColor)
    }
}

#if DEBUG
    #Preview {
        List(Bookmark.samples) { bookmark in
            BookmarkRowView(bookmark: bookmark)
        }
    }
#endif
