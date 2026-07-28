// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

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
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if bookmark.isReadLater {
                Image(systemName: "bookmark.fill")
                    .font(.caption2)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Marked to read later")
            }

            Text(bookmark.title)
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
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
                    TagPill(name: tag)
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
