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

import Fluent
import Foundation
import Vapor

// MARK: - SmartView

/// A saved query owned by a user. Runs live against the user's bookmarks, returning the ones
/// that match its conditions — every condition when `matchMode` is `all`, at least one when it
/// is `any`. The query is stored as rules, never as results. See the Smart Views section of
/// `DECISIONS.md`.
final class SmartView: Model, Content, @unchecked Sendable {

    // MARK: Static Properties

    static let schema = "smart_views"
    static let maxNameLength = 100
    static let matchAll = "all"
    static let matchAny = "any"

    // MARK: Properties

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "name")
    var name: String

    @Field(key: "conditions")
    var conditionsStore: SmartViewConditionList

    @Field(key: "match_mode")
    var matchMode: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    // MARK: Computed Properties

    var conditions: [SmartViewCondition] {
        get { conditionsStore.conditions }
        set { conditionsStore = SmartViewConditionList(conditions: newValue) }
    }

    // MARK: Lifecycle

    init() {}

    init(
        id: UUID? = nil,
        userID: User.IDValue,
        name: String,
        conditions: [SmartViewCondition],
        matchMode: String = SmartView.matchAll
    ) {
        self.id = id
        $user.id = userID
        self.name = name
        conditionsStore = SmartViewConditionList(conditions: conditions)
        self.matchMode = matchMode
    }

    // MARK: Functions

    func asResponse() throws -> SmartViewResponse {
        try SmartViewResponse(
            id: requireID(),
            name: name,
            matchMode: matchMode,
            conditions: conditions.map { SmartViewConditionPayload(type: $0.typeString, value: $0.valueString) },
            createdAt: createdAt ?? Date(),
            updatedAt: updatedAt ?? Date()
        )
    }

    func applyConditions(to builder: QueryBuilder<Bookmark>, archivedDefault: Bool = false) {
        let overridesArchived = conditions.contains { if case .isArchived = $0 { true } else { false } }
        if !overridesArchived {
            builder.filter(\.$isArchived == archivedDefault)
        }

        if matchMode == SmartView.matchAny {
            builder.group(.or) { group in
                for condition in conditions {
                    condition.apply(to: group)
                }
            }
        } else {
            for condition in conditions {
                condition.apply(to: builder)
            }
        }
    }
}

// MARK: - SmartViewConditionList

/// A single-object wrapper around the condition array. Stored as one JSON document so the
/// `conditions` column holds a `jsonb` object on PostgreSQL (not a `jsonb[]` array, which a
/// `.json` column rejects) while remaining portable to the SQLite test database.
struct SmartViewConditionList: Codable, Equatable {

    let conditions: [SmartViewCondition]
}

// MARK: - SmartViewCondition

/// A single condition in a Smart View query. Stored as a `{ type, value }` JSON object (a
/// discriminated union); all values serialize as strings. Dates are ISO-8601, `isArchived` is
/// `"true"` / `"false"`.
enum SmartViewCondition: Codable, Equatable {

    case tag(String)
    case urlContains(String)
    case titleContains(String)
    case descriptionContains(String)
    case createdBefore(Date)
    case createdAfter(Date)
    case isArchived(Bool)
    case hasTags(Bool)

    // MARK: Nested Types

    private enum CodingKeys: String, CodingKey {

        case type
        case value
    }

    // MARK: Static Properties

    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // MARK: Computed Properties

    var typeString: String {
        switch self {
        case .tag: "tag"
        case .urlContains: "urlContains"
        case .titleContains: "titleContains"
        case .descriptionContains: "descriptionContains"
        case .createdBefore: "createdBefore"
        case .createdAfter: "createdAfter"
        case .isArchived: "isArchived"
        case .hasTags: "hasTags"
        }
    }

    var valueString: String {
        switch self {
        case let .tag(value), let .urlContains(value), let .titleContains(value),
             let .descriptionContains(value):
            value
        case let .createdBefore(date), let .createdAfter(date):
            Self.iso8601.string(from: date)
        case let .isArchived(value), let .hasTags(value):
            value ? "true" : "false"
        }
    }

    // MARK: Lifecycle

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let value = try container.decode(String.self, forKey: .value)
        self = try SmartViewCondition.validated(type: type, value: value)
    }

    // MARK: Static Functions

    static func validated(type: String, value: String) throws -> SmartViewCondition {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.validationFailed("Each condition must have a non-empty value.")
        }

        switch type {
        case "tag":
            return .tag(trimmed)
        case "urlContains":
            return .urlContains(trimmed)
        case "titleContains":
            return .titleContains(trimmed)
        case "descriptionContains":
            return .descriptionContains(trimmed)
        case "createdBefore":
            guard let date = iso8601.date(from: trimmed) else {
                throw APIError.validationFailed("The date value must be a valid ISO-8601 date.")
            }

            return .createdBefore(date)
        case "createdAfter":
            guard let date = iso8601.date(from: trimmed) else {
                throw APIError.validationFailed("The date value must be a valid ISO-8601 date.")
            }

            return .createdAfter(date)
        case "isArchived":
            switch trimmed.lowercased() {
            case "true": return .isArchived(true)
            case "false": return .isArchived(false)
            default: throw APIError.validationFailed("The isArchived value must be 'true' or 'false'.")
            }
        case "hasTags":
            switch trimmed.lowercased() {
            case "true": return .hasTags(true)
            case "false": return .hasTags(false)
            default: throw APIError.validationFailed("The hasTags value must be 'true' or 'false'.")
            }
        default:
            throw APIError.validationFailed("'\(type)' is not a valid condition type.")
        }
    }

    // MARK: Functions

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(typeString, forKey: .type)
        try container.encode(valueString, forKey: .value)
    }

    func apply(to builder: QueryBuilder<Bookmark>) {
        switch self {
        case let .tag(value):
            let tag = Bookmark.normalizeTagQuery(value)
            guard !tag.isEmpty else { return }

            builder.group(.or) { group in
                group.filter(\.$tagsSearch ~~ "|\(tag)|")
                group.filter(\.$tagsSearch ~~ "|\(tag)/")
            }
        case let .urlContains(value):
            builder.filterColumn("url", contains: value)
        case let .titleContains(value):
            builder.filterColumn("title", contains: value)
        case let .descriptionContains(value):
            builder.filterColumn("description", contains: value)
        case let .createdBefore(date):
            builder.filter(\.$createdAt < date)
        case let .createdAfter(date):
            builder.filter(\.$createdAt > date)
        case let .isArchived(value):
            builder.filter(\.$isArchived == value)
        case let .hasTags(value):
            builder.filter(value ? \.$tagsSearch != "" : \.$tagsSearch == "")
        }
    }
}
