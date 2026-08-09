// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Vapor

/// A single audit-trail entry: an auth event (login success/failure, logout) or an
/// admin user-management action (create, suspend, unsuspend, password reset, TOTP
/// reset, delete, appearance change). Best-effort; see `AuditLogger` for the
/// non-throwing write contract. Deliberately narrow scope: does NOT cover bookmark,
/// tag, or smart view CRUD (too high-volume, low audit value for v1).
final class AuditLog: Model, Content, @unchecked Sendable {

    // MARK: Static Properties

    static let schema = "audit_logs"

    // MARK: Properties

    @ID(key: .id)
    var id: UUID?

    /// The username performing the action, or the attempted username on a failed
    /// login. `nil` only in edge cases where no username was ever supplied.
    @OptionalField(key: "actor_username")
    var actorUsername: String?

    /// Short slug identifying the event, e.g. `"login_success"`, `"login_failure"`,
    /// `"logout"`, `"user_created"`, `"user_suspended"`, `"user_unsuspended"`,
    /// `"password_reset"`, `"totp_reset"`, `"user_deleted"`, `"appearance_updated"`.
    @Field(key: "action")
    var action: String

    /// Free-text context, e.g. the target username plus what changed.
    @OptionalField(key: "detail")
    var detail: String?

    /// Best-effort client IP; see AuditLogger / §6 for how this is resolved.
    @OptionalField(key: "ip")
    var ip: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    // MARK: Lifecycle

    init() {}

    init(
        id: UUID? = nil,
        actorUsername: String?,
        action: String,
        detail: String? = nil,
        ip: String? = nil
    ) {
        self.id = id
        self.actorUsername = actorUsername
        self.action = action
        self.detail = detail
        self.ip = ip
    }
}
