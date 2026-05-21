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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    makeNameField()
                    makeMatchRow()
                    makeConditionsList()
                    makeErrorMessage()
                }
                .padding()
            }
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
        .frame(minWidth: 540, minHeight: 480)
        #endif
    }

    // MARK: Content Methods

    private func makeNameField() -> some View {
        TextField("Name", text: $name)
            .textFieldStyle(.roundedBorder)
    }

    private func makeMatchRow() -> some View {
        HStack(spacing: 6) {
            Text("Match")

            Picker("Match", selection: $matchMode) {
                ForEach(MatchMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()

            Text("of the following rules:")
        }
    }

    private func makeConditionsList() -> some View {
        VStack(spacing: 10) {
            ForEach($rows) { $row in
                ConditionRowView(
                    row: $row,
                    tagStore: environment.tagRepository,
                    canRemove: rows.count > 1,
                    onRemove: { remove(row) },
                    onAdd: { addRow(after: row) }
                )
            }
        }
    }

    @ViewBuilder
    private func makeErrorMessage() -> some View {
        if let errorMessage {
            Text(errorMessage)
                .foregroundStyle(.red)
                .font(.footnote)
        }
    }

    // MARK: Functions

    private func remove(_ row: ConditionRow) {
        rows.removeAll { $0.id == row.id }
    }

    private func addRow(after row: ConditionRow) {
        guard let index = rows.firstIndex(where: { $0.id == row.id }) else {
            rows.append(ConditionRow())

            return
        }

        rows.insert(ConditionRow(), at: index + 1)
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

/// The Smart View match mode bound to the popup picker, mapping to the wire `all` / `any`.
private enum MatchMode: String, CaseIterable, Identifiable {

    case all
    case any

    // MARK: Computed Properties

    var id: String {
        rawValue
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
    var duration = DurationValue()

    // MARK: Computed Properties

    var isComplete: Bool {
        switch type.valueKind {
        case .text, .tag: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .duration: duration.amount >= 1
        case .date, .boolean: true
        }
    }

    var condition: SmartViewCondition {
        let value: String = switch type.valueKind {
        case .text, .tag: text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .date: SmartViewConditionDate.wireValue(from: date)
        case .duration: SmartViewDuration(amount: duration.amount, unit: duration.unit).wireValue
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
        case .duration:
            if let parsed = SmartViewDuration(string: condition.value) {
                duration = DurationValue(amount: parsed.amount, unit: parsed.unit)
            }
        case .boolean:
            bool = condition.value.lowercased() == "true"
        }
    }
}

// MARK: - DurationValue

/// The editable state of a relative-age duration condition row: a positive amount and a unit, bound to
/// the row's number field and unit picker. Serialized to the wire value `"\(amount)\(unit.rawValue)"`.
private struct DurationValue {

    var amount = 30
    var unit: DurationUnit = .days
}

// MARK: - ConditionRowView

/// One condition row in the Music-style layout: a single horizontal line of a type popup, a value
/// editor chosen by the type's `valueKind`, and trailing remove / add buttons. The `tag` kind shows
/// the autocomplete chips the bookmark forms use beneath the row.
private struct ConditionRowView: View {

    // MARK: SwiftUI Properties

    @Binding var row: ConditionRow

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    // MARK: Properties

    let tagStore: any TagAutocompleting
    let canRemove: Bool
    let onRemove: () -> Void
    let onAdd: () -> Void

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

    /// Whether the row's controls fit on one line (regular width / macOS). A compact-width iPhone
    /// stacks the value editor under the type popup so a long type label can't clip the value or
    /// the remove / add buttons.
    private var isSingleLine: Bool {
        #if os(iOS)
            horizontalSizeClass != .compact
        #else
            true
        #endif
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isSingleLine {
                makeSingleLineLayout()
            } else {
                makeStackedLayout()
            }

            makeTagSuggestions()
        }
    }

    // MARK: Content Methods

    private func makeSingleLineLayout() -> some View {
        HStack(spacing: 8) {
            makeTypePicker()

            makeValueEditor()
                .frame(maxWidth: .infinity, alignment: .leading)

            makeRowButtons()
        }
    }

    private func makeStackedLayout() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                makeTypePicker()

                Spacer(minLength: 0)

                makeRowButtons()
            }

            makeValueEditor()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func makeTypePicker() -> some View {
        Picker("Type", selection: $row.type) {
            ForEach(SmartViewConditionType.allCases) { type in
                Text(type.title).tag(type)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }

    @ViewBuilder
    private func makeValueEditor() -> some View {
        switch row.type.valueKind {
        case .text, .tag:
            TextField(row.type.valueKind == .tag ? "tag" : "value", text: $row.text)
                .textFieldStyle(.roundedBorder)
                .lowercasedFieldStyle()
                .accessibilityLabel(row.type.title)

        case .date:
            DatePicker(row.type.title, selection: $row.date, displayedComponents: .date)
                .labelsHidden()

        case .duration:
            makeDurationEditor()

        case .boolean:
            Picker(row.type.title, selection: $row.bool) {
                Text("Yes").tag(true)
                Text("No").tag(false)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
    }

    private func makeDurationEditor() -> some View {
        HStack(spacing: 8) {
            TextField("Amount", value: $row.duration.amount, format: .number)
                .textFieldStyle(.roundedBorder)
                .numberFieldStyle()
                .frame(width: 64)
                .accessibilityLabel("\(row.type.title) amount")
                .onChange(of: row.duration.amount) { _, newValue in
                    if newValue < 1 {
                        row.duration.amount = 1
                    }
                }

            Picker(row.type.title, selection: $row.duration.unit) {
                ForEach(DurationUnit.allCases) { unit in
                    Text(unit.label).tag(unit)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    private func makeRowButtons() -> some View {
        HStack(spacing: 8) {
            Button(action: onRemove) {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .disabled(!canRemove)
            .opacity(canRemove ? 1 : 0.3)
            .accessibilityLabel("Remove Condition")

            Button(action: onAdd) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityLabel("Add Condition")
        }
        .buttonStyle(.plain)
        .font(.title3)
    }

    @ViewBuilder
    private func makeTagSuggestions() -> some View {
        if row.type.valueKind == .tag, !tagSuggestions.isEmpty {
            TagSuggestionView(suggestions: tagSuggestions) { tag in
                row.text = tag.name
            }
        }
    }
}

#if DEBUG
    #Preview {
        SmartViewFormView(repository: AppEnvironment.preview.smartViewRepository) { _ in }
            .environment(AppEnvironment.preview)
            .environment(AppSettings.preview)
    }
#endif
