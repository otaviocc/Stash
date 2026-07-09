// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Vapor

// MARK: - AuditLogger

/// Writes audit-trail entries. Best-effort and non-throwing from the caller's
/// perspective: a failed audit write is logged and swallowed, never propagated. An
/// audit-log failure must NEVER cause a login, logout, or admin action to fail —
/// the real user-facing action must always complete regardless of whether this
/// call succeeds.
enum AuditLogger {

    static func record(
        action: String,
        actor: String?,
        detail: String? = nil,
        ip: String? = nil,
        on db: any Database
    ) async {
        let entry = AuditLog(actorUsername: actor, action: action, detail: detail, ip: ip)
        do {
            try await entry.save(on: db)
        } catch {
            db.logger.error("Audit log write failed for action \(action): \(String(reflecting: error))")
        }
    }

    /// Records only when `condition` is true. For admin actions like suspend/unsuspend that always
    /// run but should only be audited when they actually change state, so callers don't each
    /// hand-roll a "did this really happen?" guard around `record`.
    static func record(
        if condition: Bool,
        action: String,
        actor: String?,
        detail: String? = nil,
        ip: String? = nil,
        on db: any Database
    ) async {
        guard condition else { return }

        await record(action: action, actor: actor, detail: detail, ip: ip, on: db)
    }
}

extension AuditLogger {

    /// Best-effort client IP: prefers `X-Forwarded-For` (set by the Caddy reverse
    /// proxy in production deployments — see Docs/backend-docker-caddy.md), falling
    /// back to the raw socket address for local/direct connections.
    static func clientIP(from req: Request) -> String? {
        if let forwarded = req.headers.first(name: "X-Forwarded-For") {
            let first = forwarded.split(separator: ",").first?.trimmingCharacters(in: .whitespaces)
            if let first, !first.isEmpty {
                return first
            }
        }
        return req.remoteAddress?.description
    }
}
