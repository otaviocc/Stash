// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Vapor

// MARK: - BootDateKey

/// Storage key for the timestamp at which this process booted. Set exactly once, in `configure(_:)`,
/// and read anywhere `Date() - bootDate` is needed to compute process uptime (e.g. the admin health
/// page). Never mutated after boot.
struct BootDateKey: StorageKey {

    typealias Value = Date
}
