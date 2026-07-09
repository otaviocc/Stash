// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Vapor

/// Reads and revokes active web sessions directly from Vapor's in-memory session store
/// (`app.sessions.memory.storage.sessions`, a public, mutable `[SessionID: SessionData]`).
/// Both the admin dashboard (`/admin`) and the app frontend (`/app`) share this single
/// dictionary, distinguished only by which session key their `SessionData` carries
/// (`AdminSessionMiddleware.sessionKey` vs. `UserSessionMiddleware.sessionKey`). Pure
/// read/write against that dictionary — no separate tracking table, no login/logout hooks.
enum ActiveSessionLoader {

    // MARK: Nested Types

    // MARK: - SessionType

    enum SessionType: String, Content {

        case admin
        case app
    }

    // MARK: - Row

    /// One resolved session, ready for display.
    struct Row {

        let id: String
        let userID: UUID
        let username: String?
        let sessionType: SessionType
        let userIsActive: Bool
    }

    // MARK: Static Functions

    // MARK: - Read

    /// Scans every live session, resolves each to a user, and optionally filters by a
    /// case-insensitive username prefix. Sessions whose stored user ID no longer matches
    /// any user are still returned, with `username` set to `nil`.
    static func loadActiveSessions(on req: Request, usernameQuery: String? = nil) async throws -> [Row] {
        let sessions = req.application.sessions.memory.storage.sessions

        var entries: [(id: SessionID, userID: UUID, type: SessionType)] = []
        for (id, data) in sessions {
            if let idString = data[AdminSessionMiddleware.sessionKey], let userID = UUID(uuidString: idString) {
                entries.append((id, userID, .admin))
            } else if let idString = data[UserSessionMiddleware.sessionKey], let userID = UUID(uuidString: idString) {
                entries.append((id, userID, .app))
            }
        }

        let userIDs = Set(entries.map(\.userID))
        let users = try await User.query(on: req.db).filter(\.$id ~~ userIDs).all()
        let usersByID = try Dictionary(uniqueKeysWithValues: users.map { try ($0.requireID(), $0) })

        var rows = entries.map { entry in
            let user = usersByID[entry.userID]
            return Row(
                id: maskedID(entry.id),
                userID: entry.userID,
                username: user?.username,
                sessionType: entry.type,
                userIsActive: user?.isActive ?? false
            )
        }

        if let query = usernameQuery?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !query.isEmpty {
            rows = rows.filter { $0.username?.lowercased().hasPrefix(query) ?? false }
        }

        return rows.sorted { ($0.username ?? "") < ($1.username ?? "") }
    }

    // MARK: - Revoke

    /// Clears every live session, both admin dashboard and app frontend. Returns the count
    /// of sessions removed.
    static func revokeAll(on app: Application) -> Int {
        let count = app.sessions.memory.storage.sessions.count
        app.sessions.memory.storage.sessions = [:]
        return count
    }

    /// Clears every live session (admin or app) belonging to a specific user.
    static func revokeForUser(userID: UUID, on app: Application) {
        var sessions = app.sessions.memory.storage.sessions
        let userIDString = userID.uuidString

        for (id, data) in sessions {
            if data[AdminSessionMiddleware.sessionKey] == userIDString
                || data[UserSessionMiddleware.sessionKey] == userIDString
            {
                sessions[id] = nil
            }
        }

        app.sessions.memory.storage.sessions = sessions
    }

    // MARK: - Private

    /// Masks a session ID for display: first 8 + last 4 characters, joined with an ellipsis.
    private static func maskedID(_ id: SessionID) -> String {
        let string = id.string
        guard string.count > 12 else { return string }

        return "\(string.prefix(8))…\(string.suffix(4))"
    }
}
