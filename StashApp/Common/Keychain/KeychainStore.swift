// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

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
/// with an app extension over an App Group (used by the Share Extension in M9). Every query also
/// sets `kSecUseDataProtectionKeychain` so macOS uses the data-protection keychain (iOS's only
/// keychain) rather than the legacy file-based one — without it, App-Group access-group sharing
/// silently fails on macOS and the extension cannot read the tokens the app wrote.
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
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
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
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true
        ]

        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }
}
