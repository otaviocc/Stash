// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - ClientMetadataFetcher

/// Fetches and parses page metadata (title, description, favicon) directly on-device.
///
/// A verbatim port of the backend's `MetadataFetcher` (Docs/product-api.md §10) so the native app and Share
/// Extension can retrieve metadata even when the Stash backend is out of reach; the browser
/// still has to reach the target site, but no round-trip through the backend is needed. `fetch`
/// never throws: on timeout / non-2xx / parse failure it returns whatever it could determine (often
/// just the `/favicon.ico` fallback, or all-nil), so an add never blocks. The 5-second timeout with
/// no retry mirrors the backend.
enum ClientMetadataFetcher {

    // MARK: Static Properties

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        return URLSession(configuration: configuration)
    }()

    // MARK: Static Functions

    static func fetch(for url: URL) async -> PageMetadata {
        var request = URLRequest(url: url)
        request.setValue("StashBot/1.0 (+https://github.com/otaviocc/stash)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return PageMetadata(title: nil, description: nil, faviconURL: defaultFavicon(for: url))
            }

            let html = String(bytes: data, encoding: .utf8) ?? ""
            return parse(html: html, baseURL: url)
        } catch {
            return PageMetadata(title: nil, description: nil, faviconURL: nil)
        }
    }

    static func parse(html: String, baseURL: URL) -> PageMetadata {
        let title = extractTitle(from: html)
        let description = extractDescription(from: html)
        let favicon = extractFavicon(from: html, baseURL: baseURL) ?? defaultFavicon(for: baseURL)
        return PageMetadata(title: title, description: description, faviconURL: favicon)
    }

    static func defaultFavicon(for baseURL: URL) -> URL? {
        guard let scheme = baseURL.scheme, let host = baseURL.host else { return nil }

        var origin = "\(scheme)://\(host)"
        if let port = baseURL.port {
            origin += ":\(port)"
        }
        return URL(string: origin + "/favicon.ico")
    }

    // MARK: Extraction

    private static func extractTitle(from html: String) -> String? {
        if let raw = firstMatch(#"<title[^>]*>(.*?)</title>"#, in: html) {
            return decodeEntities(raw).nonEmpty
        }

        return metaContent(html: html, attribute: "property", value: "og:title")
    }

    private static func extractDescription(from html: String) -> String? {
        metaContent(html: html, attribute: "name", value: "description")
            ?? metaContent(html: html, attribute: "property", value: "og:description")
    }

    private static func metaContent(html: String, attribute: String, value: String) -> String? {
        let v = NSRegularExpression.escapedPattern(for: value)
        let attrFirst = #"<meta[^>]+"# + attribute + #"\s*=\s*["']"# + v + #"["'][^>]*content\s*=\s*["']([^"']*)["']"#
        let contentFirst = #"<meta[^>]+content\s*=\s*["']([^"']*)["'][^>]*"# + attribute + #"\s*=\s*["']"# + v + #"["']"#
        if let raw = firstMatch(attrFirst, in: html) ?? firstMatch(contentFirst, in: html) {
            return decodeEntities(raw).nonEmpty
        }

        return nil
    }

    private static func extractFavicon(from html: String, baseURL: URL) -> URL? {
        let relFirst = #"<link[^>]+rel\s*=\s*["'][^"']*icon[^"']*["'][^>]*href\s*=\s*["']([^"']*)["']"#
        let hrefFirst = #"<link[^>]+href\s*=\s*["']([^"']*)["'][^>]*rel\s*=\s*["'][^"']*icon[^"']*["']"#
        guard let href = (firstMatch(relFirst, in: html) ?? firstMatch(hrefFirst, in: html))?.nonEmpty else {
            return nil
        }

        let resolved = decodeEntities(href)
        return URL(string: resolved, relativeTo: baseURL)?.absoluteURL ?? URL(string: resolved)
    }

    // MARK: Helpers

    private static func firstMatch(_ pattern: String, in html: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }

        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              match.numberOfRanges > group,
              let captured = Range(match.range(at: group), in: html) else { return nil }

        return String(html[captured])
    }

    private static func decodeEntities(_ string: String) -> String {
        var result = string
        let replacements = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&#x27;": "'",
            "&apos;": "'", "&nbsp;": " "
        ]
        for (entity, char) in replacements {
            result = result.replacingOccurrences(of: entity, with: char)
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - String + NonEmpty

private extension String {

    /// The trimmed string, or `nil` when it is empty after trimming. Mirrors the backend helper used
    /// throughout metadata extraction so blank fields stay `nil`.
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmed.isEmpty ? nil : trimmed
    }
}
