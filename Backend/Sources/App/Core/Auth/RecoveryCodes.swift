// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Generation and normalization of single-use 2FA recovery codes. PRD §8.3 / §7.4.
///
/// Format: 8 uppercase alphanumeric characters, presented in two groups for readability
/// (`ABCD-EFGH`). Eight codes are generated at enrollment.
enum RecoveryCodes {

    // MARK: Static Properties

    static let count = 8

    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

    // MARK: Static Functions

    static func generate() -> [String] {
        (0..<count).map { _ in formatted(rawCode()) }
    }

    static func normalize(_ code: String) -> String {
        code.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func rawCode() -> String {
        String((0..<8).map { _ in alphabet.randomElement()! })
    }

    private static func formatted(_ raw: String) -> String {
        let mid = raw.index(raw.startIndex, offsetBy: 4)
        return "\(raw[raw.startIndex..<mid])-\(raw[mid...])"
    }
}
