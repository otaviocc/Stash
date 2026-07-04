// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

// MARK: - SmartViewManagementView

/// Manages the user's Smart Views: create, edit, and delete. Reached from Settings (a pushed screen on
/// iOS, a Settings tab on macOS). The sidebar Smart Views section stays browse-only; because the shared
/// `SmartViewRepository` cache updates on every write, edits and deletes here are reflected there live.
struct SmartViewManagementView: View {

    // MARK: SwiftUI Properties

    @Environment(AppEnvironment.self) private var environment

    @State private var presentedForm: FormPresentation?
    @State private var pendingDelete: SmartView?
    @State private var errorMessage: String?

    // MARK: Computed Properties

    private var smartViews: [SmartView] {
        environment.smartViewRepository.smartViews
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            #if os(macOS)
                makeNewButton()
            #endif
            makeContent()
        }
        .navigationTitle("Smart Views")
        .inlineNavigationTitleStyle()
        .sheet(item: $presentedForm) { presentation in
            switch presentation {
            case .create:
                SmartViewFormView(repository: environment.smartViewRepository) { _ in }
            case let .edit(smartView):
                SmartViewFormView(editing: smartView, repository: environment.smartViewRepository) { _ in }
            }
        }
        .confirmationDialog(
            "Delete this Smart View?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { smartView in
            Button("Delete", role: .destructive) {
                delete(smartView)
            }

            Button("Cancel", role: .cancel) {}
        } message: { smartView in
            Text(smartView.name)
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            do {
                try await environment.smartViewRepository.load()
            } catch {
                errorMessage = error.stashUserMessage
            }
        }
        .smartViewNewToolbar { presentedForm = .create }
    }

    // MARK: Content Methods

    #if os(macOS)
        private func makeNewButton() -> some View {
            Button {
                presentedForm = .create
            } label: {
                Label("New Smart View", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    #endif

    @ViewBuilder
    private func makeContent() -> some View {
        if smartViews.isEmpty {
            BookmarkEmptyState(
                symbol: "line.3.horizontal.decrease.circle",
                title: "No Smart Views",
                message: "Create a saved filter to quickly find bookmarks matching specific conditions."
            )
        } else {
            List {
                ForEach(smartViews) { smartView in
                    makeRow(for: smartView)
                }
            }
        }
    }

    private func makeRow(for smartView: SmartView) -> some View {
        Button {
            presentedForm = .edit(smartView)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(smartView.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Text(summary(for: smartView))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button(role: .destructive) {
                pendingDelete = smartView
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                presentedForm = .edit(smartView)
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button(role: .destructive) {
                pendingDelete = smartView
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: Functions

    private func summary(for smartView: SmartView) -> String {
        let match = smartView.matchMode == "any" ? "Any" : "All"
        let count = smartView.conditions.count
        let unit = count == 1 ? "condition" : "conditions"

        return "\(match) · \(count) \(unit)"
    }

    private func delete(_ smartView: SmartView) {
        Task {
            do {
                try await environment.smartViewRepository.delete(id: smartView.id)
            } catch {
                errorMessage = error.stashUserMessage
            }
        }
    }
}

// MARK: - New Smart View Toolbar

private extension View {

    /// Adds a "New Smart View" toolbar button on iOS, where this screen is pushed in a navigation
    /// stack with a toolbar; a no-op on macOS, where it is a `Settings` tab with no toolbar surface
    /// (the in-content `makeNewButton` provides the affordance there instead).
    @ViewBuilder
    func smartViewNewToolbar(action: @escaping () -> Void) -> some View {
        #if os(iOS)
            toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: action) {
                        Label("New Smart View", systemImage: "plus")
                    }
                }
            }
        #else
            self
        #endif
    }
}

// MARK: - FormPresentation

/// Which form the sheet shows: creating a new Smart View, or editing an existing one.
private enum FormPresentation: Identifiable {

    case create
    case edit(SmartView)

    // MARK: Computed Properties

    var id: String {
        switch self {
        case .create: "create"
        case let .edit(smartView): smartView.id.uuidString
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            SmartViewManagementView()
        }
        .environment(AppEnvironment.preview)
        .environment(AppSettings.preview)
    }
#endif
