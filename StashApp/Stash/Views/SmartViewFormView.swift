// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

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
            Form {
                makeNameSection()
                makeConditionsSection()
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
        .frame(minWidth: 540, minHeight: 480)
        #endif
    }

    // MARK: Content Methods

    private func makeNameSection() -> some View {
        Section {
            TextField("Name", text: $name)
        }
    }

    private func makeConditionsSection() -> some View {
        Section {
            makeMatchRow()
            makeConditionRows()
            makeAddConditionButton()
        } header: {
            Text("Conditions")
        } footer: {
            makeErrorMessage()
        }
    }

    private func makeMatchRow() -> some View {
        Picker("Match", selection: $matchMode) {
            ForEach(MatchMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.menu)
    }

    private func makeConditionRows() -> some View {
        ForEach($rows) { $row in
            makeConditionRow($row)
                .deleteDisabled(rows.count <= 1)
        }
        .onDelete(perform: removeRows)
    }

    @ViewBuilder
    private func makeConditionRow(_ binding: Binding<ConditionRow>) -> some View {
        let row = ConditionRowView(row: binding, tagStore: environment.tagRepository)
            .contextMenu {
                Button(role: .destructive) {
                    remove(binding.wrappedValue)
                } label: {
                    Label("Delete Condition", systemImage: "trash")
                }
                .disabled(rows.count <= 1)
            }

        #if os(macOS)
            HStack(spacing: 8) {
                row

                Button {
                    remove(binding.wrappedValue)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(rows.count > 1 ? .red : .secondary)
                }
                .buttonStyle(.borderless)
                .disabled(rows.count <= 1)
                .accessibilityLabel("Delete Condition")
            }
        #else
            row
        #endif
    }

    private func makeAddConditionButton() -> some View {
        Button {
            rows.append(ConditionRow())
        } label: {
            Label("Add Condition", systemImage: "plus")
        }
        .formButtonRowStyle()
    }

    @ViewBuilder
    private func makeErrorMessage() -> some View {
        if let errorMessage {
            Text(errorMessage)
                .foregroundStyle(.red)
        }
    }

    // MARK: Functions

    private func remove(_ row: ConditionRow) {
        rows.removeAll { $0.id == row.id }
    }

    private func removeRows(at offsets: IndexSet) {
        rows.remove(atOffsets: offsets)
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

    var label: String {
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
    /// stacks the value editor under the type popup so a long type label can't clip the value.
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

            Spacer(minLength: 8)

            makeValueEditor()
        }
    }

    private func makeStackedLayout() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            makeTypePicker()
                .frame(maxWidth: .infinity, alignment: .leading)

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
                .multilineTextAlignment(isSingleLine ? .trailing : .leading)
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
                .multilineTextAlignment(.trailing)
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
