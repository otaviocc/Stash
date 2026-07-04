// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - SmartViewDTO

/// A saved query that filters bookmarks by a set of conditions, combined with `matchMode`
/// (`"all"` = every condition must match, `"any"` = at least one).
public struct SmartViewDTO: Codable, Identifiable, Sendable {

    // MARK: Nested Types

    private enum CodingKeys: String, CodingKey {

        case id
        case name
        case matchMode
        case conditions
        case createdAt
        case updatedAt
    }

    // MARK: Properties

    public let id: UUID
    public let name: String
    public let matchMode: String
    public let conditions: [SmartViewConditionDTO]
    public let createdAt: Date
    public let updatedAt: Date

    // MARK: Lifecycle

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        matchMode = try container.decodeIfPresent(String.self, forKey: .matchMode) ?? "all"
        conditions = try container.decode([SmartViewConditionDTO].self, forKey: .conditions)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

// MARK: - SmartViewConditionDTO

/// A single condition in a Smart View query. All values are strings. The `type` is one of `tag`,
/// `urlContains`, `titleContains`, `descriptionContains`, `createdBefore` / `createdAfter` (absolute
/// ISO-8601 dates), `olderThan` / `newerThan` (a relative duration string — a positive integer with a
/// `d`/`m`/`y` unit suffix, e.g. `"30d"`, `"3m"`, `"1y"`), `isArchived`, or `hasTags` (`"true"` /
/// `"false"`).
public struct SmartViewConditionDTO: Codable, Sendable {

    // MARK: Properties

    public let type: String
    public let value: String

    // MARK: Lifecycle

    public init(type: String, value: String) {
        self.type = type
        self.value = value
    }
}
