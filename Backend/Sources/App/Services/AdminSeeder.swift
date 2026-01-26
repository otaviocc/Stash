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
import Vapor

/// First-boot admin account seeding (PRD §16).
enum AdminSeeder {

    @discardableResult
    static func seed(
        username rawUsername: String?,
        password: String?,
        on db: Database,
        logger: Logger,
        hash: (String) async throws -> String
    ) async throws -> Bool {
        let userCount = try await User.query(on: db).count()
        guard userCount == 0 else {
            return false
        }
        guard let username = rawUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
              let password,
              !username.isEmpty, !password.isEmpty
        else {
            logger.critical(
                "No users exist and ADMIN_USERNAME / ADMIN_PASSWORD are not both set. Cannot create the admin account. Set both environment variables and restart."
            )
            throw Abort(
                .internalServerError,
                reason: "Missing ADMIN_USERNAME / ADMIN_PASSWORD for first-boot admin seeding."
            )
        }
        guard password.count >= 12 else {
            logger.critical("ADMIN_PASSWORD must be at least 12 characters. The admin account was not created.")
            throw Abort(.internalServerError, reason: "ADMIN_PASSWORD must be at least 12 characters.")
        }

        let admin = try await User(username: username, passwordHash: hash(password), role: .admin)
        try await admin.save(on: db)
        logger.notice("First boot: created admin account '\(admin.username)'.")
        return true
    }
}
