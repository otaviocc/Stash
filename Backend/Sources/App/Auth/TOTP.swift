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

import Crypto
import Foundation

// MARK: - TOTP

/// RFC 6238 Time-based One-Time Password generator/validator (HMAC-SHA1, 6 digits, 30s step).
///
/// Implemented natively on `swift-crypto` (already a transitive Vapor dependency) rather than
/// pulling in a third-party TOTP package — keeps the backend dependency-light per the PRD's
/// data-ownership philosophy.
struct TOTP {

    // MARK: Properties

    let secret: Data
    var digits = 6
    var period = 30

    // MARK: Functions

    func generate(at date: Date = Date()) -> String {
        let counter = UInt64(date.timeIntervalSince1970 / Double(period))
        return code(forCounter: counter)
    }

    func validate(_ candidate: String, at date: Date = Date(), window: Int = 1) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespaces)
        let counter = Int64(date.timeIntervalSince1970 / Double(period))
        for delta in -window...window {
            let stepped = counter + Int64(delta)
            guard stepped >= 0 else { continue }
            if code(forCounter: UInt64(stepped)) == trimmed { return true }
        }
        return false
    }

    private func code(forCounter counter: UInt64) -> String {
        var bigEndian = counter.bigEndian
        let counterData = withUnsafeBytes(of: &bigEndian) { Data($0) }
        let mac = HMAC<Insecure.SHA1>.authenticationCode(
            for: counterData,
            using: SymmetricKey(data: secret)
        )
        let hash = Data(mac)
        let offset = Int(hash[hash.count - 1] & 0x0F)
        let truncated = (UInt32(hash[offset] & 0x7F) << 24)
            | (UInt32(hash[offset + 1]) << 16)
            | (UInt32(hash[offset + 2]) << 8)
            | UInt32(hash[offset + 3])
        let modulo = UInt32(pow(10.0, Double(digits)))
        let otp = truncated % modulo
        return String(format: "%0\(digits)d", otp)
    }
}

extension TOTP {

    static func generateSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 20)
        for i in bytes.indices {
            bytes[i] = UInt8.random(in: .min ... .max)
        }
        return Base32.encode(Data(bytes))
    }

    static func otpauthURI(secret: String, username: String, issuer: String = "Stash") -> String {
        var components = URLComponents()
        components.scheme = "otpauth"
        components.host = "totp"
        components.path = "/\(issuer):\(username)"
        components.queryItems = [
            URLQueryItem(name: "secret", value: secret),
            URLQueryItem(name: "issuer", value: issuer),
            URLQueryItem(name: "algorithm", value: "SHA1"),
            URLQueryItem(name: "digits", value: "6"),
            URLQueryItem(name: "period", value: "30")
        ]
        return components.string ?? "otpauth://totp/\(issuer):\(username)?secret=\(secret)&issuer=\(issuer)"
    }
}
