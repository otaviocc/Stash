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
import StashKit

// MARK: - SmartView

/// A saved query owned by the user, shown in the sidebars and run live against the bookmarks. The
/// native apps consume Smart Views (browse and open them); creating and editing them is done from the
/// web frontend.
struct SmartView: Identifiable, Hashable {

    let id: UUID
    let name: String
    let matchMode: String
    let conditions: [SmartViewCondition]
}

// MARK: - SmartView + DTO

extension SmartView {

    init(
        dto: SmartViewDTO
    ) {
        id = dto.id
        name = dto.name
        matchMode = dto.matchMode
        conditions = dto.conditions.map(SmartViewCondition.init(dto:))
    }
}

// MARK: - SmartViewCondition

/// One `{ type, value }` rule of a Smart View, kept verbatim from the wire shape.
struct SmartViewCondition: Hashable {

    let type: String
    let value: String
}

// MARK: - SmartViewCondition + DTO

extension SmartViewCondition {

    // MARK: Computed Properties

    var dto: SmartViewConditionDTO {
        SmartViewConditionDTO(type: type, value: value)
    }

    // MARK: Lifecycle

    init(
        dto: SmartViewConditionDTO
    ) {
        type = dto.type
        value = dto.value
    }
}

// MARK: - SmartViewConditionValueKind

/// The editor a condition row shows for its value, selected by the condition's type.
enum SmartViewConditionValueKind {

    case text
    case tag
    case date
    case boolean
}

// MARK: - SmartViewConditionType

/// The condition types the form can build, mirroring the backend's accepted `type` strings. `title`
/// is the human-facing label; `valueKind` drives which value editor the row renders.
enum SmartViewConditionType: String, CaseIterable, Identifiable {

    case tag
    case urlContains
    case titleContains
    case descriptionContains
    case createdBefore
    case createdAfter
    case isArchived
    case hasTags

    // MARK: Computed Properties

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .tag: "Tag"
        case .urlContains: "URL contains"
        case .titleContains: "Title contains"
        case .descriptionContains: "Description contains"
        case .createdBefore: "Created before"
        case .createdAfter: "Created after"
        case .isArchived: "Is archived"
        case .hasTags: "Has tags"
        }
    }

    var valueKind: SmartViewConditionValueKind {
        switch self {
        case .tag: .tag
        case .urlContains, .titleContains, .descriptionContains: .text
        case .createdBefore, .createdAfter: .date
        case .isArchived, .hasTags: .boolean
        }
    }
}

// MARK: - SmartViewConditionDate

/// Converts between a `DatePicker` `Date` and the wire value the date conditions expect. The backend
/// requires a full ISO-8601 datetime (not a bare `YYYY-MM-DD`), so the selected calendar day is
/// serialized at `00:00:00Z` — matching the web frontend, which sends the day and lets the server
/// append `T00:00:00Z`.
enum SmartViewConditionDate {

    // MARK: Static Properties

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: Static Functions

    static func wireValue(from date: Date) -> String {
        dayFormatter.string(from: date) + "T00:00:00Z"
    }

    static func date(from wireValue: String) -> Date {
        dayFormatter.date(from: String(wireValue.prefix(10))) ?? Date()
    }
}
