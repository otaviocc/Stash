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
        List {
            makeNewButtonRow()
            makeContentSection()
        }
        .settingsChromeStyle()
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
    }

    // MARK: Content Methods

    private func makeNewButtonRow() -> some View {
        Section {
            Button {
                presentedForm = .create
            } label: {
                Label("New Smart View", systemImage: "plus")
            }
        }
    }

    @ViewBuilder
    private func makeContentSection() -> some View {
        if smartViews.isEmpty {
            Section {
                Text("No Smart Views yet. Create one to save a query you use often.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        } else {
            Section {
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
