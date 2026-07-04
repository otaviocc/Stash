// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - SmartViewRequest

/// Request body for creating or updating a Smart View.
public struct SmartViewRequest: Encodable, Sendable {

    // MARK: Properties

    public let name: String
    public let matchMode: String
    public let conditions: [SmartViewConditionDTO]

    // MARK: Lifecycle

    public init(name: String, conditions: [SmartViewConditionDTO], matchMode: String = "all") {
        self.name = name
        self.matchMode = matchMode
        self.conditions = conditions
    }
}
