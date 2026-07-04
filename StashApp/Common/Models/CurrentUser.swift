// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import StashKit

// MARK: - CurrentUser

/// The signed-in user's profile, as needed by the Settings screen.
struct CurrentUser {

    let username: String
    let isTOTPEnabled: Bool
}

// MARK: - CurrentUser + DTO

extension CurrentUser {

    init(
        dto: UserDTO
    ) {
        username = dto.username
        isTOTPEnabled = dto.isTOTPEnabled
    }
}

// MARK: - TOTPSetup

/// The data shown while enrolling in two-factor authentication: the shared secret and the
/// `otpauth://` URI a native client renders as a QR code.
struct TOTPSetup {

    let secret: String
    let otpauthURI: String
}
