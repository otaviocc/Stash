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

/// A single condition in a Smart View query. All values are strings; dates are ISO-8601 and
/// `isArchived` is `"true"` / `"false"`.
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
