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

import Foundation

/// RFC 4648 Base32 (no padding on encode) — used for TOTP secrets.
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
