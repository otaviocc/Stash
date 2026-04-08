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

// MARK: - SmartViewFormView

/// The shared create / edit Smart View sheet: a name, a match mode (All / Any), and a list of
/// condition rows whose value editor adapts to the condition type. Used for both creating a new Smart
/// View and editing an existing one; the host presents it as a sheet and reacts via `onSaved`.
struct SmartViewFormView: View {

    // MARK: SwiftUI Properties

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var matchMode: MatchMode
    @State private var rows: [ConditionRow]
    @State private var isSaving = false
    @State private var errorMessage: String?

    // MARK: Properties

    private let editingID: UUID?
    private let repository: SmartViewRepository
    private let onSaved: (SmartView) -> Void

    // MARK: Computed Properties

    private var isEditing: Bool {
        editingID != nil
    }

    private var isValid: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName.count <= 100, !rows.isEmpty else {
            return false
        }

        return rows.allSatisfy(\.isComplete)
    }

    // MARK: Lifecycle

    init(
        repository: SmartViewRepository,
        onSaved: @escaping (SmartView) -> Void
    ) {
        editingID = nil
        self.repository = repository
        self.onSaved = onSaved
        _name = State(initialValue: "")
        _matchMode = State(initialValue: .all)
        _rows = State(initialValue: [ConditionRow()])
    }

    init(
        editing smartView: SmartView,
        repository: SmartViewRepository,
        onSaved: @escaping (SmartView) -> Void
    ) {
        editingID = smartView.id
        self.repository = repository
        self.onSaved = onSaved
        _name = State(initialValue: smartView.name)
        _matchMode = State(initialValue: MatchMode(rawValue: smartView.matchMode) ?? .all)
        let rows = smartView.conditions.map(ConditionRow.init(condition:))
        _rows = State(initialValue: rows.isEmpty ? [ConditionRow()] : rows)
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $name)
                        .labelsHidden()
                }

                Section {
                    Picker("Match", selection: $matchMode) {
                        ForEach(MatchMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } header: {
                    Text("Match")
                } footer: {
                    Text(matchMode == .all
                        ? "A bookmark must match every condition."
                        : "A bookmark must match at least one condition.")
                }

                Section("Conditions") {
                    ForEach($rows) { $row in
                        ConditionRowView(
                            row: $row,
                            tagStore: environment.tagRepository,
                            canRemove: rows.count > 1
                        ) {
                            remove(row)
                        }
                    }

                    Button {
                        rows.append(ConditionRow())
                    } label: {
                        Label("Add Condition", systemImage: "plus")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Smart View" : "New Smart View")
            .inlineNavigationTitleStyle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!isValid || isSaving)
                }
            }
            .task {
                try? await environment.tagRepository.load()
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }

    // MARK: Functions

    private func remove(_ row: ConditionRow) {
        rows.removeAll { $0.id == row.id }
    }

    private func save() {
        errorMessage = nil
        isSaving = true

        Task {
            defer { isSaving = false }

            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let conditions = rows.map(\.condition)

            do {
                let saved: SmartView = if let editingID {
                    try await repository.update(
                        id: editingID,
                        name: trimmedName,
                        matchMode: matchMode.rawValue,
                        conditions: conditions
                    )
                } else {
                    try await repository.create(
                        name: trimmedName,
                        matchMode: matchMode.rawValue,
                        conditions: conditions
                    )
                }

                onSaved(saved)
                dismiss()
            } catch {
                errorMessage = error.stashUserMessage
            }
        }
    }
}

// MARK: - MatchMode

/// The Smart View match mode bound to the segmented picker, mapping to the wire `all` / `any`.
private enum MatchMode: String, CaseIterable, Identifiable {

    case all
    case any

    // MARK: Computed Properties

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all: "All"
        case .any: "Any"
        }
    }
}

// MARK: - ConditionRow

/// The editable state of one condition row. It carries a value for every editor kind and exposes the
/// one selected by the current type, so switching type preserves what the user typed in the others.
private struct ConditionRow: Identifiable {

    // MARK: Properties

    let id = UUID()
    var type: SmartViewConditionType = .tag
    var text = ""
    var date = Date()
    var bool = false

    // MARK: Computed Properties

    var isComplete: Bool {
        switch type.valueKind {
        case .text, .tag: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .date, .boolean: true
        }
    }

    var condition: SmartViewCondition {
        let value: String = switch type.valueKind {
        case .text, .tag: text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .date: SmartViewConditionDate.wireValue(from: date)
        case .boolean: bool ? "true" : "false"
        }

        return SmartViewCondition(type: type.rawValue, value: value)
    }

    // MARK: Lifecycle

    init() {}

    init(condition: SmartViewCondition) {
        type = SmartViewConditionType(rawValue: condition.type) ?? .tag

        switch type.valueKind {
        case .text, .tag:
            text = condition.value
        case .date:
            date = SmartViewConditionDate.date(from: condition.value)
        case .boolean:
            bool = condition.value.lowercased() == "true"
        }
    }
}

// MARK: - ConditionRowView

/// One condition row: a type picker over a value editor chosen by the type's `valueKind`, plus an
/// optional remove control. The `tag` kind reuses the tag autocomplete chips the bookmark forms use.
private struct ConditionRowView: View {

    // MARK: SwiftUI Properties

    @Binding var row: ConditionRow

    // MARK: Properties

    let tagStore: any TagAutocompleting
    let canRemove: Bool
    let onRemove: () -> Void

    // MARK: Computed Properties

    private var tagSuggestions: [Tag] {
        let segment = row.text.trimmingCharacters(in: .whitespaces)
        guard !segment.isEmpty else {
            return []
        }

        return tagStore
            .autocompleteTags(prefix: segment)
            .filter { $0.name != segment }
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Type", selection: $row.type) {
                    ForEach(SmartViewConditionType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .labelsHidden()

                Spacer()

                if canRemove {
                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Remove Condition")
                }
            }

            valueEditor
        }
    }

    @ViewBuilder
    private var valueEditor: some View {
        switch row.type.valueKind {
        case .text:
            TextField("Value", text: $row.text)
                .lowercasedFieldStyle()

        case .tag:
            TextField("Tag", text: $row.text)
                .lowercasedFieldStyle()

            if !tagSuggestions.isEmpty {
                TagSuggestionView(suggestions: tagSuggestions) { tag in
                    row.text = tag.name
                }
            }

        case .date:
            DatePicker("Date", selection: $row.date, displayedComponents: .date)
                .labelsHidden()

        case .boolean:
            Picker("Value", selection: $row.bool) {
                Text("Yes").tag(true)
                Text("No").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}
