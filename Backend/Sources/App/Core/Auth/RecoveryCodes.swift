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
