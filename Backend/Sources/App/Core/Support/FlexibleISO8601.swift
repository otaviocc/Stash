// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Parses an ISO-8601 timestamp, trying the plain form first and falling back to one with
/// fractional seconds. Shared by every place that has to accept a `createdAt`/`usedAt`-style
/// string from an untrusted or externally-produced document (a Stash JSON import, an instance
/// backup restore) where the exact sub-second precision isn't guaranteed.
enum FlexibleISO8601 {

    // MARK: Static Properties

    private static let plain = ISO8601DateFormatter()
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // MARK: Static Functions

    static func date(from string: String?) -> Date? {
        guard let string else { return nil }

        return plain.date(from: string) ?? fractional.date(from: string)
    }
}
