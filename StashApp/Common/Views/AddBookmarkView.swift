// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

// MARK: - AddBookmarkView

/// The shared add-bookmark form, used by both the main app's `AddBookmarkSheet` and the Share
/// Extension's `ShareExtensionView`.
///
/// The form owns its own field state and surfaces metadata fetch and tag selection via the
/// `TagPickerSheet`. Its data dependencies are the narrow `BookmarkCreating`/`TagAutocompleting`
/// protocols, so it does not know whether it is talking to the app's repositories or the extension's
/// lightweight ones. Saving and cancelling are reported through the `onSaved`/`onCancel` callbacks
/// rather than handled here, so the host decides whether to dismiss (app) or advance to a
/// confirmation screen (extension).
///
/// When `isURLEditable` is `true` (the app) the URL field is editable with a paste button and an
/// explicit "Fetch Metadata" button. When `false` (the extension) the URL arrives from the share
/// sheet, is shown read-only, and metadata is fetched automatically on appear.
struct AddBookmarkView: View {

    // MARK: SwiftUI Properties

    @State private var urlText: String
    @State private var title = ""
    @State private var description = ""
    @State private var selectedTags: [String] = []
    @State private var isReadLater = false
    @State private var fetchedDomain: String?
    @State private var fetchTask: Task<Void, Never>?
    @State private var isFetching = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    // MARK: Properties

    let bookmarkStore: any BookmarkCreating
    let tagStore: any TagAutocompleting
    let isURLEditable: Bool
    let autoFetchOnAppear: Bool
    let usesInlineActionBar: Bool
    let onSaved: (Bookmark) -> Void
    let onCancel: () -> Void

    // MARK: Computed Properties

    private var trimmedURL: String {
        urlText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedURL: URL? {
        let trimmed = trimmedURL
        guard
            let url = URL(string: trimmed),
            url.scheme != nil,
            url.host() != nil
        else {
            return nil
        }

        return url
    }

    // MARK: Lifecycle

    init(
        initialURL: String = "",
        restoring restoredBookmark: Bookmark? = nil,
        isURLEditable: Bool,
        autoFetchOnAppear: Bool,
        usesInlineActionBar: Bool = false,
        bookmarkStore: any BookmarkCreating,
        tagStore: any TagAutocompleting,
        onSaved: @escaping (Bookmark) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _urlText = State(initialValue: restoredBookmark?.url.absoluteString ?? initialURL)
        _title = State(initialValue: restoredBookmark?.title ?? "")
        _description = State(initialValue: restoredBookmark?.description ?? "")
        _selectedTags = State(initialValue: restoredBookmark?.tags ?? [])
        _isReadLater = State(initialValue: restoredBookmark?.isReadLater ?? false)
        self.isURLEditable = isURLEditable
        self.autoFetchOnAppear = autoFetchOnAppear
        self.usesInlineActionBar = usesInlineActionBar
        self.bookmarkStore = bookmarkStore
        self.tagStore = tagStore
        self.onSaved = onSaved
        self.onCancel = onCancel
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                URLSectionView(
                    urlText: $urlText,
                    isURLEditable: isURLEditable,
                    isFetching: isFetching,
                    canFetch: !trimmedURL.isEmpty && fetchedDomain == nil,
                    fetchDisabled: parsedURL == nil,
                    errorMessage: errorMessage,
                    onFetch: fetchMetadata
                )
                Divider().opacity(0.3)
                MetadataPreviewSectionView(domain: fetchedDomain)
                TitleSectionView(title: $title)
                Divider().opacity(0.3)
                DescriptionSectionView(description: $description)
                Divider().opacity(0.3)

                TagSummarySection(selectedTags: $selectedTags, tagHierarchy: tagStore.tagHierarchy)
                Divider().opacity(0.3)
                ReadLaterSectionView(isReadLater: $isReadLater)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onChange(of: urlText) {
                fetchTask?.cancel()

                if fetchedDomain != nil {
                    withAnimation {
                        fetchedDomain = nil
                    }
                }
            }
            .navigationTitle("Add Bookmark")
            .inlineNavigationTitleStyle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    makeSaveButton()
                }
            }
            .task {
                try? await tagStore.load()

                if autoFetchOnAppear {
                    fetchMetadata()
                }
            }
            .onDisappear {
                fetchTask?.cancel()
            }
            #if os(macOS)
            .safeAreaInset(edge: .bottom) {
                if usesInlineActionBar {
                    makeMacActionBar()
                }
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }

    // MARK: Content Methods

    #if os(macOS)
        private func makeMacActionBar() -> some View {
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(parsedURL == nil || isSaving)
            }
            .padding()
            .background(.bar)
        }
    #endif

    @ViewBuilder
    private func makeSaveButton() -> some View {
        if isSaving {
            ProgressView()
                .controlSize(.small)
        } else {
            Button("Save", action: save)
                .disabled(parsedURL == nil)
        }
    }

    // MARK: Functions

    private func fetchMetadata() {
        guard let url = parsedURL else {
            return
        }

        errorMessage = nil
        isFetching = true
        fetchTask?.cancel()

        fetchTask = Task {
            defer { isFetching = false }

            let metadata = await bookmarkStore.fetchMetadata(for: url)
            guard !Task.isCancelled else {
                return
            }

            if let fetchedTitle = metadata.title, !fetchedTitle.isEmpty {
                title = fetchedTitle
            }

            if let fetchedDescription = metadata.description, !fetchedDescription.isEmpty {
                description = fetchedDescription
            }

            withAnimation {
                fetchedDomain = Bookmark.faviconDomain(for: url)
            }
        }
    }

    private func save() {
        guard let url = parsedURL else {
            return
        }

        errorMessage = nil
        isSaving = true

        Task {
            defer { isSaving = false }

            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
            let input = CreateBookmarkInput(
                url: url,
                title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                tags: selectedTags,
                fetchMetadata: true,
                isReadLater: isReadLater
            )

            do {
                let bookmark = try await bookmarkStore.create(input)
                onSaved(bookmark)
            } catch {
                errorMessage = error.stashUserMessage
            }
        }
    }
}

// MARK: - URLSectionView

/// The URL field, its paste/fetch controls, and the inline fetch-error message. Extracted so editing
/// the title or description elsewhere in `AddBookmarkView` doesn't re-diff this section too.
private struct URLSectionView: View {

    // MARK: SwiftUI Properties

    @Binding var urlText: String

    // MARK: Properties

    let isURLEditable: Bool
    let isFetching: Bool
    let canFetch: Bool
    let fetchDisabled: Bool
    let errorMessage: String?
    let onFetch: () -> Void

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: "URL")

            if isURLEditable {
                HStack(spacing: 8) {
                    TextField("https://…", text: $urlText)
                        .textFieldStyle(.plain)
                        .urlFieldStyle()

                    PasteButton(payloadType: String.self) { strings in
                        guard let pasted = strings.first else {
                            return
                        }

                        urlText = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.circle)

                    makeFetchButton()
                }
            } else {
                Text(urlText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            makeInlineError()
        }
        .fieldSectionPadding()
    }

    // MARK: Content Methods

    @ViewBuilder
    private func makeFetchButton() -> some View {
        if isFetching {
            ProgressView()
                .controlSize(.small)
        } else if canFetch {
            Button("Fetch", action: onFetch)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(fetchDisabled)
        }
    }

    @ViewBuilder
    private func makeInlineError() -> some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - MetadataPreviewSectionView

/// The fetched favicon/domain preview shown once metadata comes back. Extracted so it doesn't share
/// an invalidation boundary with the fields around it.
private struct MetadataPreviewSectionView: View {

    // MARK: Properties

    let domain: String?

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        if let domain {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    MetadataFaviconView(domain: domain, size: 24)
                    Text(domain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .fieldSectionPadding()

                Divider().opacity(0.3)
            }
            .transition(.opacity)
        }
    }
}

// MARK: - TitleSectionView

/// The title field. Extracted so it doesn't share an invalidation boundary with the fields around it.
private struct TitleSectionView: View {

    // MARK: SwiftUI Properties

    @Binding var title: String

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: "Title")
            TextField("Title", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
        }
        .fieldSectionPadding()
    }
}

// MARK: - DescriptionSectionView

/// The description field. Extracted so it doesn't share an invalidation boundary with the fields
/// around it.
private struct DescriptionSectionView: View {

    // MARK: SwiftUI Properties

    @Binding var description: String

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: "Description")
            DescriptionEditor(text: $description)
        }
        .fieldSectionPadding()
        .frame(maxHeight: .infinity)
    }
}

// MARK: - ReadLaterSectionView

/// The read-later toggle. Extracted so it doesn't share an invalidation boundary with the fields
/// above it.
private struct ReadLaterSectionView: View {

    // MARK: SwiftUI Properties

    @Binding var isReadLater: Bool

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        Toggle(isOn: $isReadLater) {
            Label("Read Later", systemImage: "bookmark.fill")
        }
        .fieldSectionPadding()
    }
}

#if DEBUG
    #Preview("Add — editable URL") {
        AddBookmarkView(
            isURLEditable: true,
            autoFetchOnAppear: false,
            bookmarkStore: PreviewBookmarkStore(),
            tagStore: PreviewTagStore(),
            onSaved: { _ in },
            onCancel: {}
        )
    }

    #Preview("Add — locked URL (share sheet)") {
        AddBookmarkView(
            initialURL: "https://swift.org",
            isURLEditable: false,
            autoFetchOnAppear: false,
            bookmarkStore: PreviewBookmarkStore(),
            tagStore: PreviewTagStore(),
            onSaved: { _ in },
            onCancel: {}
        )
    }
#endif
