// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Vapor

/// Response for `GET /api/v1/instance` (PRD §9.x). Public, unauthenticated instance chrome that
/// non-web clients (native apps, CLI) can read before or after login.
struct InstanceResponse: Content {

    // MARK: Nested Types

    struct Accent: Content {

        let theme: String
        let light: String
        let dark: String
    }

    // MARK: Properties

    let accent: Accent
}
