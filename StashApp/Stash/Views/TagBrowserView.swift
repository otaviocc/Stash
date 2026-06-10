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

// MARK: - TagBrowserView

/// A read-only list of the user's tags with counts. Filtering and rename/delete arrive later.
struct TagBrowserView: View {

    // MARK: SwiftUI Properties

    @Environment(AppEnvironment.self) private var environment

    @State private var errorMessage: String?

    // MARK: Computed Properties

    private var tags: [Tag] {
        environment.tagRepository.tags
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        List {
            ForEach(tags) { tag in
                NavigationLink {
                    BookmarkListView(tag: tag.name)
                } label: {
                    HStack {
                        Text(tag.name)
                        Spacer()
                        Text("\(tag.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay {
            if tags.isEmpty {
                ContentUnavailableView(
                    "No Tags",
                    systemImage: "tag",
                    description: Text("Tags from your bookmarks appear here.")
                )
            }
        }
        .navigationTitle("Tags")
        .refreshable {
            await load(force: true)
        }
        .task {
            await load(force: false)
        }
    }

    // MARK: Functions

    private func load(force: Bool) async {
        if force {
            environment.tagRepository.invalidateCache()
        }

        do {
            try await environment.tagRepository.load()
        } catch {
            errorMessage = error.stashUserMessage
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            TagBrowserView()
        }
        .environment(AppEnvironment.preview)
    }
#endif
