// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

/// Tag normalization and URL validation mirroring the backend's `Bookmark` rules, so the CLI's
/// local import path counts skipped records the same way the server would reject them.
enum BookmarkInput {

    static func validatedURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else {
            return nil
        }

        return trimmed
    }

    static func normalizeTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in tags {
            let tag = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .replacingOccurrences(of: "|", with: "")
            guard !tag.isEmpty else {
                continue
            }

            if seen.insert(tag).inserted {
                result.append(tag)
            }
        }

        return result
    }
}
