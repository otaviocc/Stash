// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Vapor

/// Fetches and parses page metadata (title, description, favicon). See Docs/product-api.md §10.
///
/// `fetch` never throws: on timeout / non-2xx / parse failure it returns whatever it could
/// determine (often just the `/favicon.ico` fallback, or all-nil), so a bookmark save is never
/// blocked. The 5-second timeout with no retry is configured on `app.http.client` in `configure`.
enum MetadataFetcher {

    static func fetch(url: String, on req: Request) async -> MetadataResponse {
        guard let baseURL = URL(string: url) else {
            return MetadataResponse(title: nil, description: nil, faviconURL: nil)
        }

        do {
            var headers = HTTPHeaders()
            headers.add(name: .userAgent, value: StashUserAgent.value)
            headers.add(name: .accept, value: "text/html,application/xhtml+xml")

            let response = try await req.client.get(URI(string: url), headers: headers)
            guard response.status == .ok, var body = response.body else {
                return MetadataResponse(title: nil, description: nil, faviconURL: defaultFavicon(for: baseURL))
            }

            let html = body.readString(length: body.readableBytes, encoding: .utf8) ?? ""
            return parse(html: html, baseURL: baseURL)
        } catch {
            req.logger.debug("Metadata fetch failed for \(url): \(String(reflecting: error))")
            return MetadataResponse(title: nil, description: nil, faviconURL: nil)
        }
    }

    static func parse(html: String, baseURL: URL) -> MetadataResponse {
        let title = extractTitle(from: html)
        let description = extractDescription(from: html)
        let favicon = extractFavicon(from: html, baseURL: baseURL) ?? defaultFavicon(for: baseURL)
        return MetadataResponse(title: title, description: description, faviconURL: favicon)
    }

    static func defaultFavicon(for baseURL: URL) -> String? {
        guard let scheme = baseURL.scheme, let host = baseURL.host else { return nil }

        var origin = "\(scheme)://\(host)"
        if let port = baseURL.port {
            origin += ":\(port)"
        }
        return origin + "/favicon.ico"
    }

    // MARK: - Extraction

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

    private static func extractFavicon(from html: String, baseURL: URL) -> String? {
        let relFirst = #"<link[^>]+rel\s*=\s*["'][^"']*icon[^"']*["'][^>]*href\s*=\s*["']([^"']*)["']"#
        let hrefFirst = #"<link[^>]+href\s*=\s*["']([^"']*)["'][^>]*rel\s*=\s*["'][^"']*icon[^"']*["']"#
        guard let href = (firstMatch(relFirst, in: html) ?? firstMatch(hrefFirst, in: html))?.nonEmpty else {
            return nil
        }

        let resolved = decodeEntities(href)
        return URL(string: resolved, relativeTo: baseURL)?.absoluteString ?? resolved
    }

    // MARK: - Helpers

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
