// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import UniformTypeIdentifiers

/// Extracts the shared URL from a Share Extension's input items.
///
/// Safari and most apps attach the page URL as a `public.url` item provider; some share the page as
/// `public.plain-text` instead, in which case the first URL-looking token in the text is used. The
/// first match across all input items wins.
///
/// `@MainActor`-isolated so the non-`Sendable` `NSExtensionItem`/`NSItemProvider` values never cross
/// an actor boundary; only the resolved `URL`/`String` results return across the continuation.
@MainActor
enum SharedItemLoader {

    static func loadURL(from items: [NSExtensionItem]) async -> URL? {
        let providers = items.flatMap { $0.attachments ?? [] }

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = await loadURL(from: provider) {
                return url
            }
        }

        for provider in providers
            where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        {
            if let text = await loadText(from: provider), let url = firstURL(in: text) {
                return url
            }
        }

        return nil
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                continuation.resume(returning: coerceURL(from: item))
            }
        }
    }

    private nonisolated static func coerceURL(from item: (any NSSecureCoding)?) -> URL? {
        switch item {
        case let url as URL:
            url

        case let string as String:
            URL(string: string)

        case let data as Data:
            URL(dataRepresentation: data, relativeTo: nil)
                ?? String(data: data, encoding: .utf8).flatMap { URL(string: $0) }

        default:
            nil
        }
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                continuation.resume(returning: item as? String)
            }
        }
    }

    private static func firstURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let match = detector?.firstMatch(in: text, options: [], range: range)

        return match?.url
    }
}
