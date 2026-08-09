// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

// MARK: - TagPickerSheet

/// A sheet for selecting and creating tags from the user's tag hierarchy. The sole tag-editing
/// surface for the add and edit bookmark forms on both platforms: touch-first, no keyboard required
/// to pick existing tags.
///
/// The search field doubles as new-tag input: when the query matches no existing tag a "Create" row
/// appears at the top, and tapping it normalizes the query (mirroring the backend) and adds it to the
/// selection without closing the sheet. Selection is a live binding: every tap commits immediately,
/// so there is no Cancel; Done and swipe-down both leave the selection as edited.
struct TagPickerSheet: View {

    // MARK: SwiftUI Properties

    @Binding var selectedTags: [String]

    @State private var searchText = ""

    // MARK: Properties

    let tagHierarchy: [TagNode]
    var onDismiss: () -> Void

    /// Every slug in `tagHierarchy`, walked once at `init` rather than recomputed from a computed
    /// property; `tagHierarchy` doesn't change for the sheet's lifetime, but a computed property
    /// would otherwise re-walk the whole tree on every `searchText` keystroke since `showsCreateRow`
    /// reads it in `body`.
    private let allSlugs: Set<String>

    // MARK: Computed Properties

    private var normalizedQuery: String {
        searchText.normalizedTagQuery()
    }

    private var filteredHierarchy: [TagNode] {
        Self.filtered(tagHierarchy, query: searchText.trimmingCharacters(in: .whitespaces))
    }

    private var showsCreateRow: Bool {
        !normalizedQuery.isEmpty && !allSlugs.contains(normalizedQuery)
    }

    // MARK: Lifecycle

    init(
        selectedTags: Binding<[String]>,
        tagHierarchy: [TagNode],
        onDismiss: @escaping () -> Void
    ) {
        _selectedTags = selectedTags
        self.tagHierarchy = tagHierarchy
        self.onDismiss = onDismiss
        allSlugs = Self.collectSlugs(tagHierarchy)
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                makeSearchField()
                Divider()
                makeSelectedChips()
                makeContent()
            }
            .animation(.default, value: selectedTags.isEmpty)
            .navigationTitle("Tags")
            .inlineNavigationTitleStyle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #else
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    // MARK: Content Methods

    private func makeSearchField() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search or add tag…", text: $searchText)
                .textFieldStyle(.plain)
                .lowercasedFieldStyle()
                .onSubmit(createTag)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func makeSelectedChips() -> some View {
        if !selectedTags.isEmpty {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedTags, id: \.self) { tag in
                            SelectedTagChip(tag: tag) {
                                selectedTags.removeAll { $0 == tag }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }

                Divider()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func makeContent() -> some View {
        if filteredHierarchy.isEmpty, !showsCreateRow {
            makeEmptyState()
        } else {
            List {
                if showsCreateRow {
                    Section {
                        makeCreateRow()
                    }
                }

                Section {
                    ForEach(filteredHierarchy.flattened()) { item in
                        makeTagRow(item.node, depth: item.depth)
                    }
                }
            }
        }
    }

    private func makeCreateRow() -> some View {
        Button(action: createTag) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .imageScale(.medium)
                    .foregroundStyle(Color.accentColor)
                Text("Create \"\(normalizedQuery)\"")
                    .font(.body)
                    .fontWeight(.medium)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func makeTagRow(_ node: TagNode, depth: Int) -> some View {
        let isSelected = selectedTags.contains(node.slug)

        return Button {
            toggle(node.slug)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "circle.fill" : "circle")
                    .imageScale(.medium)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                TagTreeLabel(node: node, depth: depth)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func makeEmptyState() -> some View {
        if searchText.isEmpty {
            BookmarkEmptyState(
                symbol: "tag",
                title: "No tags yet",
                message: "Type a name above to create your first tag."
            )
        } else {
            ContentUnavailableView(
                "No Matches",
                systemImage: "magnifyingglass",
                description: Text("No tag matches your search.")
            )
        }
    }

    // MARK: Static Functions

    /// Filters the tag tree against the query, keeping a parent visible whenever any descendant
    /// matches so the hierarchy stays navigable. When a parent matches by its own name its full
    /// unfiltered subtree is kept (so its children remain selectable); when it survives only because
    /// a descendant matches, just the matching branch is kept.
    static func filtered(_ nodes: [TagNode], query: String) -> [TagNode] {
        guard !query.isEmpty else {
            return nodes
        }

        return nodes.compactMap { node in
            let nameMatches = node.label.localizedCaseInsensitiveContains(query)
            let filteredChildren = filtered(node.children ?? [], query: query)

            if nameMatches {
                return node
            }

            if !filteredChildren.isEmpty {
                return TagNode(
                    slug: node.slug,
                    label: node.label,
                    count: node.count,
                    totalCount: node.totalCount,
                    children: filteredChildren
                )
            }

            return nil
        }
    }

    /// Every slug in the tree, walked once (see `allSlugs`).
    private static func collectSlugs(_ nodes: [TagNode]) -> Set<String> {
        func collect(_ nodes: [TagNode]) -> [String] {
            nodes.flatMap { [$0.slug] + collect($0.children ?? []) }
        }

        return Set(collect(nodes))
    }

    // MARK: Functions

    private func toggle(_ slug: String) {
        if let index = selectedTags.firstIndex(of: slug) {
            selectedTags.remove(at: index)
        } else {
            selectedTags.append(slug)
        }
    }

    private func createTag() {
        let tag = normalizedQuery
        guard !tag.isEmpty else {
            return
        }

        if !selectedTags.contains(tag) {
            selectedTags.append(tag)
        }

        searchText = ""
    }
}

#if DEBUG
    #Preview {
        @Previewable @State var selected = ["swift/server"]
        Color.clear
            .sheet(isPresented: .constant(true)) {
                TagPickerSheet(
                    selectedTags: $selected,
                    tagHierarchy: Tag.samples.hierarchy()
                ) {}
            }
    }
#endif
