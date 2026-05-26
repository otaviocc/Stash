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

        func fetchMetadata(for _: URL) async throws -> PageMetadata {
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
