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

/// A single-use 2FA recovery code. See PRD §7.4 and §8.4.
///
/// Eight codes are generated at 2FA enrolment. Only the bcrypt hash is stored.
final class RecoveryCode: Model, @unchecked Sendable {

    // MARK: Static Properties

    static let schema = "recovery_codes"

    // MARK: Properties

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    /// Bcrypt hash of the raw (normalised, dash-free, uppercased) code.
    @Field(key: "code_hash")
    var codeHash: String

    /// Null until redeemed; once set, the code cannot be reused.
    @OptionalField(key: "used_at")
    var usedAt: Date?

    // MARK: Lifecycle

    init() {}

    init(id: UUID? = nil, userID: User.IDValue, codeHash: String, usedAt: Date? = nil) {
        self.id = id
        $user.id = userID
        self.codeHash = codeHash
        self.usedAt = usedAt
    }
}
