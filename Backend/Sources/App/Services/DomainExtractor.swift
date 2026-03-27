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
