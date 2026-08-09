// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// RFC 4648 Base32 (no padding on encode), used for TOTP secrets.
enum Base32 {

    // MARK: Static Properties

    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    // MARK: Static Functions

    static func encode(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }

        var output = ""
        var buffer = 0
        var bitsLeft = 0
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bitsLeft += 8
            while bitsLeft >= 5 {
                let index = (buffer >> (bitsLeft - 5)) & 0x1F
                bitsLeft -= 5
                output.append(alphabet[index])
            }
        }
        if bitsLeft > 0 {
            let index = (buffer << (5 - bitsLeft)) & 0x1F
            output.append(alphabet[index])
        }
        return output
    }

    static func decode(_ string: String) -> Data? {
        let cleaned = string.uppercased().filter { $0 != "=" && !$0.isWhitespace }
        var lookup = [Character: Int]()
        for (i, c) in alphabet.enumerated() {
            lookup[c] = i
        }

        var buffer = 0
        var bitsLeft = 0
        var bytes = [UInt8]()
        for char in cleaned {
            guard let value = lookup[char] else { return nil }

            buffer = (buffer << 5) | value
            bitsLeft += 5
            if bitsLeft >= 8 {
                let byte = (buffer >> (bitsLeft - 8)) & 0xFF
                bytes.append(UInt8(byte))
                bitsLeft -= 8
            }
        }
        return Data(bytes)
    }
}
