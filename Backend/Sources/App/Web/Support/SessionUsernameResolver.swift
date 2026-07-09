// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation
import Vapor

/// Looks up the username behind a web session cookie's stored user id, for logout audit entries
/// where the session is about to be (or has just been) destroyed. Shared by the admin dashboard
/// and the `/app` frontend so both surfaces resolve a logging-out user's username the same way.
enum SessionUsernameResolver {

    static func resolve(fromSessionKey key: String, req: Request) async throws -> String? {
        guard let idString = req.session.data[key], let id = UUID(uuidString: idString) else {
            return nil
        }

        return try await User.find(id, on: req.db)?.username
    }
}
