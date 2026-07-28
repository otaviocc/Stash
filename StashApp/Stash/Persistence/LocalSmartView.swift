// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import StashKit
import SwiftData

// MARK: - LocalSmartView

/// A locally persisted Smart View definition, so the sidebars and the management screen can show the
/// user's saved queries on a cold launch even before (or without) reaching the server.
///
/// Unlike `LocalBookmark`, there is no local/server id split and no `pendingSyncAt`/`isLocalOnly`
/// pair: Smart Views are never authored offline (create/edit/delete always go straight to the
/// server), so every row here always mirrors a real server record and `id` doubles as the server's own
/// id. `conditionsData` stores the JSON-encoded `[SmartViewConditionDTO]` verbatim — the same
/// `{type, value}` wire shape `SmartViewCondition` already mirrors — rather than a typed array, since
/// SwiftData has no native support for an array of a custom `Codable` struct as an attribute.
@Model
final class LocalSmartView {

    // MARK: Properties

    @Attribute(.unique) var id: UUID

    /// The server ID of the user who owns this Smart View. Set at insert time and used to scope every
    /// read, so a previous user's cached Smart Views on a shared device are never visible to the next
    /// signed-in user, even though (unlike bookmarks) the on-disk rows aren't wiped on every sign-out
    /// path — see `LocalStore.wipe(currentUserID:)`.
    var userID: String
    var name: String
    var matchMode: String
    var conditionsData: Data
    var serverUpdatedAt: Date

    // MARK: Computed Properties

    /// Decodes `conditionsData` back into its wire-shaped conditions.
    var conditions: [SmartViewConditionDTO] {
        (try? JSONDecoder().decode([SmartViewConditionDTO].self, from: conditionsData)) ?? []
    }

    // MARK: Lifecycle

    init(dto: SmartViewDTO, userID: String) {
        id = dto.id
        self.userID = userID
        name = dto.name
        matchMode = dto.matchMode
        conditionsData = (try? JSONEncoder().encode(dto.conditions)) ?? Data()
        serverUpdatedAt = dto.updatedAt
    }

    // MARK: Functions

    /// Overwrites every field with a fresh DTO, since the applied data is always authoritative server
    /// state (there is no local/pending state here to preserve).
    func apply(_ dto: SmartViewDTO) {
        name = dto.name
        matchMode = dto.matchMode
        conditionsData = (try? JSONEncoder().encode(dto.conditions)) ?? Data()
        serverUpdatedAt = dto.updatedAt
    }
}

// MARK: - SmartView + LocalSmartView

extension SmartView {

    /// Maps a persisted record to the view-facing domain model.
    init(local: LocalSmartView) {
        id = local.id
        name = local.name
        matchMode = local.matchMode
        conditions = local.conditions.map(SmartViewCondition.init(dto:))
    }
}
