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

/// The Tags tab: the bookmark-list "Views" (All, Untagged, Today, This Week) over a collapsible,
/// hierarchical tag tree mirroring the web sidebar. Each entry drills into a filtered bookmark list.
struct TagBrowserView: View {

    // MARK: SwiftUI Properties

    @Environment(AppEnvironment.self) private var environment

    @State private var errorMessage: String?

    // MARK: Computed Properties

    private var nodes: [TagNode] {
        environment.tagRepository.tags.hierarchy()
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        List {
            Section("Views") {
                viewLink("All Bookmarks", systemImage: "bookmark", tag: nil)
                viewLink("Untagged", systemImage: "tag.slash", tag: Bookmark.untaggedSentinel)
                viewLink("Today", systemImage: "sun.max", tag: Bookmark.todaySentinel)
                viewLink("This Week", systemImage: "calendar", tag: Bookmark.thisWeekSentinel)
            }

            if !nodes.isEmpty {
                Section("Tags") {
                    OutlineGroup(nodes, children: \.children) { node in
                        NavigationLink {
                            BookmarkListView(tag: node.slug)
                        } label: {
                            TagTreeLabel(node: node)
                        }
                    }
                }
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

    // MARK: Content Methods

    private func viewLink(_ title: String, systemImage: String, tag: String?) -> some View {
        NavigationLink {
            BookmarkListView(tag: tag)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    // MARK: Functions

    private func load(force: Bool) async {
        do {
            if force {
                try await environment.tagRepository.reload()
            } else {
                try await environment.tagRepository.load()
            }
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
        .environment(AppSettings.preview)
    }
#endif
