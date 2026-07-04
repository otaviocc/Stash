// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

extension DateFormatter {

    /// Medium date + short time, the shared timestamp rendering across the web UIs (bookmark rows,
    /// the admin user detail).
    static let webDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
