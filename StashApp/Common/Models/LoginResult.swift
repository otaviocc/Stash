// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

/// The result of a login attempt.
enum LoginResult {

    case authenticated
    case requires2FA(tempToken: String)
}
