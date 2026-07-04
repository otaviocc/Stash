// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Extracts a favicon cache key and origin from a bookmark URL. Parses with `URLComponents` — the
/// same parser `Bookmark.validatedURL` uses — so a URL that validates resolves a consistent host.
enum DomainExtractor {

    static func domain(from urlString: String) -> String? {
        guard let components = URLComponents(string: urlString),
              var host = components.host?.lowercased(), !host.isEmpty
        else {
            return nil
        }

        if host.hasPrefix("www.") {
            host = String(host.dropFirst(4))
            guard !host.isEmpty else { return nil }
        }

        if let port = components.port {
            return "\(host):\(port)"
        }

        return host
    }

    static func origin(from urlString: String) -> String? {
        guard let components = URLComponents(string: urlString),
              let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty
        else {
            return nil
        }

        var origin = "\(scheme)://\(host)"
        if let port = components.port {
            origin += ":\(port)"
        }

        return origin
    }
}
