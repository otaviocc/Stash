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

/// Pure presentation helpers for Smart Views in the web frontend: condition summaries/labels, the
/// results-page URL, and the two-way mapping between stored `SmartViewCondition`s and the Leaf form's
/// `SmartViewConditionField`s. Validation and duration parsing are delegated to the Core
/// `SmartViewCondition` / `SmartViewDuration` types — this only shapes them for display and forms.
enum SmartViewPresenter {

    // MARK: Static Computed Properties

    static var defaultField: SmartViewConditionField {
        field(type: "tag", rawValue: "")
    }

    // MARK: Static Functions

    static func smartViewListURL(id: String, archived: Bool, page: Int) -> String {
        var components = URLComponents()
        components.path = "/app/smart-views/\(id)"
        var items: [URLQueryItem] = []
        if archived { items.append(.init(name: "archived", value: "true")) }

        if page > 1 { items.append(.init(name: "page", value: String(page))) }

        components.queryItems = items.isEmpty ? nil : items
        return components.string ?? "/app/smart-views/\(id)"
    }

    static func summary(for conditions: [SmartViewCondition], matchMode: String) -> String {
        let prefix = matchMode == SmartView.matchAny ? "Match any" : "Match all"
        let labels = conditions.map { conditionLabel($0) }.joined(separator: ", ")

        return "\(prefix): \(labels)"
    }

    static func conditionLabel(_ condition: SmartViewCondition) -> String {
        switch condition {
        case let .tag(value): "Tag: \(value)"
        case let .urlContains(value): "URL contains “\(value)”"
        case let .titleContains(value): "Title contains “\(value)”"
        case let .descriptionContains(value): "Description contains “\(value)”"
        case let .createdBefore(date): "Created before \(SmartViewCondition.iso8601.string(from: date).prefix(10))"
        case let .createdAfter(date): "Created after \(SmartViewCondition.iso8601.string(from: date).prefix(10))"
        case let .olderThan(value): "Older than \(durationPhrase(value))"
        case let .newerThan(value): "Newer than \(durationPhrase(value))"
        case let .isArchived(value): "Archived: \(value ? "Yes" : "No")"
        case let .hasTags(value): "Has tags: \(value ? "Yes" : "No")"
        }
    }

    /// Renders a compact duration string (`"30d"`) as a readable phrase (`"30 days"`), falling back to
    /// the raw value if it can't be parsed.
    static func durationPhrase(_ value: String) -> String {
        guard let duration = SmartViewDuration(string: value) else { return value }

        let unit: String = switch duration.unit {
        case .days: duration.value == 1 ? "day" : "days"
        case .months: duration.value == 1 ? "month" : "months"
        case .years: duration.value == 1 ? "year" : "years"
        }

        return "\(duration.value) \(unit)"
    }

    static func normalizedConditionValue(type: String, value: String) -> String {
        guard type == "createdBefore" || type == "createdAfter" else { return value }

        if value.count == 10, value.contains("-"), !value.contains("T") {
            return value + "T00:00:00Z"
        }

        return value
    }

    static func conditions(from form: SmartViewForm) throws -> [SmartViewCondition] {
        let types = form.conditionType ?? []
        let values = form.conditionValue ?? []
        var result: [SmartViewCondition] = []
        for (index, type) in types.enumerated() {
            let raw = (index < values.count ? values[index] : "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }

            try result.append(SmartViewCondition.validated(
                type: type,
                value: normalizedConditionValue(type: type, value: raw)
            ))
        }
        guard !result.isEmpty else {
            throw APIError.validationFailed("Add at least one condition with a value.")
        }

        return result
    }

    static func fields(from form: SmartViewForm) -> [SmartViewConditionField] {
        let types = form.conditionType ?? []
        let values = form.conditionValue ?? []
        var fields: [SmartViewConditionField] = []
        for (index, type) in types.enumerated() {
            let value = index < values.count ? values[index] : ""
            fields.append(field(type: type, rawValue: value))
        }
        return fields.isEmpty ? [defaultField] : fields
    }

    static func field(from condition: SmartViewCondition) -> SmartViewConditionField {
        let type = condition.typeString
        var raw = condition.valueString
        if type == "createdBefore" || type == "createdAfter" {
            raw = String(raw.prefix(10))
        }

        return field(type: type, rawValue: raw)
    }

    static func field(type: String, rawValue: String) -> SmartViewConditionField {
        let isBool = type == "isArchived" || type == "hasTags"
        let isDate = type == "createdBefore" || type == "createdAfter"
        let isDuration = type == "olderThan" || type == "newerThan"
        let boolValue = (isBool && rawValue.lowercased() == "false") ? "false" : "true"
        let duration = isDuration ? SmartViewDuration(string: rawValue) : nil
        let durationAmount = duration.map { String($0.value) } ?? "30"
        let durationUnit = duration?.unit.rawValue ?? "d"

        let textInputType: String = isDuration ? "hidden" : (isDate ? "date" : "text")
        let textValue: String = if isBool {
            ""
        } else if isDuration {
            durationAmount + durationUnit
        } else {
            rawValue
        }

        return SmartViewConditionField(
            type: type,
            textValue: textValue,
            boolValue: boolValue,
            durationAmount: durationAmount,
            durationUnit: durationUnit,
            textInputType: textInputType,
            isBool: isBool,
            hideBool: !isBool,
            hideDuration: !isDuration
        )
    }
}
