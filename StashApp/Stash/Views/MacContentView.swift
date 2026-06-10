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

#if os(macOS)
    import SwiftUI

    // MARK: - MacContentView

    /// The authenticated macOS shell: a `NavigationSplitView` whose sidebar (All Bookmarks, Untagged,
    /// and the tag list) filters the bookmark list in the detail column. Selecting a bookmark pushes its
    /// detail within the detail column's navigation stack, the same shared `BookmarkListView` /
    /// `BookmarkDetailView` the iPad layout uses.
    struct MacContentView: View {

        // MARK: SwiftUI Properties

        @Environment(AppEnvironment.self) private var environment

        @State private var selection: MacSidebarItem? = .all

        // MARK: Content Properties

        // MARK: Content

        var body: some View {
            NavigationSplitView {
                List(selection: $selection) {
                    Label("All Bookmarks", systemImage: "bookmark")
                        .tag(MacSidebarItem.all)
                    Label("Untagged", systemImage: "tag.slash")
                        .tag(MacSidebarItem.untagged)

                    Section("Tags") {
                        ForEach(environment.tagRepository.tags) { tag in
                            HStack {
                                Text(tag.name)
                                Spacer()
                                Text("\(tag.count)")
                                    .foregroundStyle(.secondary)
                            }
                            .tag(MacSidebarItem.tag(tag.name))
                        }
                    }
                }
                .navigationTitle("Stash")
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
                .task {
                    try? await environment.tagRepository.load()
                }
            } detail: {
                NavigationStack {
                    BookmarkListView(tag: selection?.tagFilter)
                }
            }
        }
    }

    // MARK: - MacSidebarItem

    /// A selectable entry in the macOS sidebar.
    private enum MacSidebarItem: Hashable {

        case all
        case untagged
        case tag(String)

        // MARK: Computed Properties

        /// The `tag` filter passed to `BookmarkListView`: `nil` for all, the untagged sentinel, or the
        /// literal tag.
        var tagFilter: String? {
            switch self {
            case .all: nil
            case .untagged: "__untagged__"
            case let .tag(name): name
            }
        }
    }

#endif
