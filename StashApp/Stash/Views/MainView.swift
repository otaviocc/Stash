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

#if os(iOS)

    // MARK: - MainView

    /// The authenticated app shell: a tag-sidebar split view on iPad, a tab bar on iPhone.
    struct MainView: View {

        // MARK: SwiftUI Properties

        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        // MARK: Content Properties

        // MARK: Content

        var body: some View {
            if horizontalSizeClass == .regular {
                SidebarSplitView()
            } else {
                TabContainerView()
            }
        }
    }

    // MARK: - SidebarSplitView

    /// The iPad layout: a tag list in the sidebar driving a filtered bookmark list in the detail column.
    private struct SidebarSplitView: View {

        // MARK: SwiftUI Properties

        @Environment(AppEnvironment.self) private var environment

        @State private var selection: SidebarItem? = .all

        // MARK: Content Properties

        // MARK: Content

        var body: some View {
            NavigationSplitView {
                List(selection: $selection) {
                    Label("All Bookmarks", systemImage: "bookmark")
                        .tag(SidebarItem.all)

                    Section("Tags") {
                        ForEach(environment.tagRepository.tags) { tag in
                            HStack {
                                Text(tag.name)
                                Spacer()
                                Text("\(tag.count)")
                                    .foregroundStyle(.secondary)
                            }
                            .tag(SidebarItem.tag(tag.name))
                        }
                    }
                }
                .navigationTitle("Stash")
                .task {
                    try? await environment.tagRepository.load()
                }
            } detail: {
                NavigationStack {
                    BookmarkListView(tag: selection?.tagName)
                }
            }
        }
    }

    // MARK: - SidebarItem

    /// A selectable entry in the iPad sidebar.
    private enum SidebarItem: Hashable {

        case all
        case tag(String)

        // MARK: Computed Properties

        var tagName: String? {
            switch self {
            case .all: nil
            case let .tag(name): name
            }
        }
    }

    #if DEBUG
        #Preview {
            MainView()
                .environment(AppEnvironment.preview)
                .environment(AppSettings())
        }
    #endif

#endif
