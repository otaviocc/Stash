// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Vapor

// MARK: - SmartViewConditionPayload

/// A single Smart View condition on the wire — a `{ type, value }` pair, both strings.
struct SmartViewConditionPayload: Content {

    let type: String
    let value: String
}

// MARK: - SmartViewRequestBody

/// `POST` / `PUT /smart-views` body — the display name, the match mode (`all` / `any`), and the
/// (unvalidated) condition list. `matchMode` is optional: omitting it defaults to `all` on create
/// and leaves the existing value unchanged on update.
struct SmartViewRequestBody: Content {

    // MARK: Properties

    let name: String
    let matchMode: String?
    let conditions: [SmartViewConditionPayload]

    // MARK: Lifecycle

    init(name: String, conditions: [SmartViewConditionPayload], matchMode: String? = nil) {
        self.name = name
        self.matchMode = matchMode
        self.conditions = conditions
    }
}

// MARK: - SmartViewResponse

/// Public Smart View projection returned by the API.
struct SmartViewResponse: Content {

    let id: UUID
    let name: String
    let matchMode: String
    let conditions: [SmartViewConditionPayload]
    let createdAt: Date
    let updatedAt: Date
}
