// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

#if DEBUG
    import Foundation

    // MARK: - Sample data

    extension Bookmark {

        static let sample = Bookmark(
            id: UUID(),
            url: URL(string: "https://swift.org")!,
            title: "Swift.org — Welcome to Swift",
            description: "Swift is a general-purpose programming language built using a modern approach to safety, performance, and software design patterns.",
            faviconURL: URL(string: "https://swift.org/favicon.ico"),
            tags: ["swift", "swift/server", "ios"],
            isArchived: false,
            createdAt: Date(timeIntervalSince1970: 1_770_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_770_000_000)
        )

        static let samples: [Bookmark] = [
            sample,
            Bookmark(
                id: UUID(),
                url: URL(string: "https://www.pointfree.co")!,
                title: "Point-Free",
                description: "A video series on functional programming and the Swift language.",
                faviconURL: nil,
                tags: ["swift", "functional"],
                isArchived: false,
                createdAt: Date(timeIntervalSince1970: 1_769_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_769_000_000)
            ),
            Bookmark(
                id: UUID(),
                url: URL(string: "https://news.ycombinator.com")!,
                title: "Hacker News",
                description: nil,
                faviconURL: nil,
                tags: [],
                isArchived: false,
                createdAt: Date(timeIntervalSince1970: 1_768_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_768_000_000)
            )
        ]
    }

    extension Tag {

        static let samples: [Tag] = [
            Tag(name: "swift", count: 24, totalCount: 24),
            Tag(name: "swift/server", count: 8, totalCount: 12),
            Tag(name: "ios", count: 15, totalCount: 15),
            Tag(name: "functional", count: 0, totalCount: 3)
        ]
    }

    extension PageMetadata {

        static let sample = PageMetadata(
            title: "Swift.org — Welcome to Swift",
            description: "Swift is a general-purpose programming language.",
            faviconURL: URL(string: "https://swift.org/favicon.ico")
        )
    }

    // MARK: - PreviewBookmarkStore

    /// A `BookmarkCreating` stand-in for previews that returns sample data without any network.
    @MainActor
    @Observable
    final class PreviewBookmarkStore: BookmarkCreating {

        func create(_: CreateBookmarkInput) async throws -> Bookmark {
            .sample
        }

        func fetchMetadata(for _: URL) async -> PageMetadata {
            .sample
        }
    }

    // MARK: - PreviewTagStore

    /// A `TagAutocompleting` stand-in for previews, preloaded with sample tags.
    @MainActor
    @Observable
    final class PreviewTagStore: TagAutocompleting {

        // MARK: Properties

        var tags: [Tag] = Tag.samples

        // MARK: Computed Properties

        var tagHierarchy: [TagNode] {
            tags.hierarchy()
        }

        // MARK: Functions

        func load() async throws {}

        func autocompleteTags(prefix: String) -> [Tag] {
            tags.autocomplete(prefix: prefix)
        }
    }
#endif
