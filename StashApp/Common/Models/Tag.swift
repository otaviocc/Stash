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

// MARK: - Tag

/// A tag with its usage count.
struct Tag: Identifiable, Hashable {

    // MARK: Properties

    let name: String
    let count: Int

    // MARK: Computed Properties

    var id: String {
        name
    }
}

// MARK: - Tag + DTO

extension Tag {

    init(
        dto: TagDTO
    ) {
        name = dto.name
        count = dto.count
    }
}

// MARK: - Tag autocomplete

extension [Tag] {

    /// Returns tags whose name — or any `/`-delimited segment of it — begins with the given prefix,
    /// case-insensitively. Mirrors the web frontend's per-segment autocomplete, so typing `music`
    /// surfaces `music`, `kind/music-gear`, and `learning/music-theory`.
    func autocomplete(prefix: String) -> [Tag] {
        let needle = prefix.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else {
            return []
        }

        return filter { tag in
            tag.name
                .lowercased()
                .split(separator: "/", omittingEmptySubsequences: false)
                .contains { $0.hasPrefix(needle) }
        }
    }
}
