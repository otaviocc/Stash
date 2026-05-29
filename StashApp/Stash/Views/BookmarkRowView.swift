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

/// A single bookmark row laid out as a hierarchy: the domain (with favicon) as the scannable anchor,
/// the title as the primary content, a two-line description excerpt, and text-only tags as a quiet
/// tertiary line.
struct BookmarkRowView: View {

    // MARK: Properties

    let bookmark: Bookmark

    // MARK: Computed Properties

    private var domain: String {
        bookmark.faviconDomain ?? bookmark.hostname
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            makeDomainLine()
            makeTitle()
            makeDescription()
            makeTags()
        }
        .padding(.vertical, 10)
    }

    // MARK: Content Methods

    private func makeDomainLine() -> some View {
        HStack(spacing: 6) {
            FaviconView(domain: bookmark.faviconDomain)
            Text(domain)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if bookmark.isPendingSync || bookmark.hasSyncError {
                Spacer(minLength: 8)
                PendingSyncBadge(failed: bookmark.hasSyncError)
            }
        }
    }

    private func makeTitle() -> some View {
        Text(bookmark.title)
            .font(.body)
            .fontWeight(.medium)
            .foregroundStyle(.primary)
            .lineLimit(2)
    }

    @ViewBuilder
    private func makeDescription() -> some View {
        if let description = bookmark.description, !description.isEmpty {
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private func makeTags() -> some View {
        if !bookmark.tags.isEmpty {
            HStack(spacing: 10) {
                ForEach(bookmark.tags.prefix(3), id: \.self) { tag in
                    TagPill(name: tag, isPlain: true)
                }

                if bookmark.tags.count > 3 {
                    Text("+\(bookmark.tags.count - 3)")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
            .lineLimit(1)
        }
    }
}

#if DEBUG
    #Preview {
        List(Bookmark.samples) { bookmark in
            BookmarkRowView(bookmark: bookmark)
        }
        .environment(AppSettings.preview)
    }
#endif
