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
import Security

// MARK: - KeychainStoreProtocol

/// A read/write store for a single secret string, abstracting the backing store for testing.
protocol KeychainStoreProtocol: AnyObject, Sendable {

    var wrappedValue: String? { get set }
}

// MARK: - KeychainStore

/// A Keychain-backed store for a single secret string, keyed by account.
///
/// Reads via `SecItemCopyMatching` and writes via a delete-then-add against a generic-password
/// item whose `kSecAttrAccount` is the supplied key. Setting `nil` deletes the item. The Security
/// framework calls are injected so the store can be exercised without touching the real Keychain.
///
/// An optional `accessGroup` adds `kSecAttrAccessGroup` to every query so the item can be shared
/// with an app extension over an App Group (used by the Share Extension in M9).
final class KeychainStore: KeychainStoreProtocol, @unchecked Sendable {

    // MARK: Nested Types

    typealias ItemDeleter = (CFDictionary) -> OSStatus
    typealias ItemAdder = (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    typealias ItemCopyMatcher = (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus

    // MARK: Properties

    private let key: String
    private let accessGroup: String?
    private let itemDeleter: ItemDeleter
    private let itemAdder: ItemAdder
    private let itemCopyMatcher: ItemCopyMatcher

    // MARK: Computed Properties

    var wrappedValue: String? {
        get {
            var query = baseQuery()
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne

            var result: CFTypeRef?
            let status = itemCopyMatcher(query as CFDictionary, &result)
            guard
                status == errSecSuccess,
                let data = result as? Data,
                let string = String(data: data, encoding: .utf8)
            else {
                return nil
            }

            return string
        }

        set {
            let query = baseQuery()
            _ = itemDeleter(query as CFDictionary)

            guard let newValue, let data = newValue.data(using: .utf8) else {
                return
            }

            var addQuery = query
            addQuery[kSecValueData as String] = data
            _ = itemAdder(addQuery as CFDictionary, nil)
        }
    }

    // MARK: Lifecycle

    init(
        _ key: String,
        accessGroup: String? = nil,
        itemDeleter: @escaping ItemDeleter = SecItemDelete,
        itemAdder: @escaping ItemAdder = SecItemAdd,
        itemCopyMatcher: @escaping ItemCopyMatcher = SecItemCopyMatching
    ) {
        self.key = key
        self.accessGroup = accessGroup
        self.itemDeleter = itemDeleter
        self.itemAdder = itemAdder
        self.itemCopyMatcher = itemCopyMatcher
    }

    // MARK: Functions

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }
}
