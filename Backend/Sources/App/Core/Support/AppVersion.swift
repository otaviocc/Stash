// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Vapor

// MARK: - AppVersionKey

/// Storage key for the application version string.
struct AppVersionKey: StorageKey {

    typealias Value = String
}

// MARK: - AppVersion

/// Reads the instance version from the `VERSION` file at the working directory root, falling back
/// to `"dev"` when the file is missing or empty. The file is copied into the Docker image.
enum AppVersion {

    static func read(directory: String) -> String {
        let base = directory.hasSuffix("/") ? directory : directory + "/"
        guard let raw = try? String(contentsOfFile: base + "VERSION", encoding: .utf8) else {
            return "dev"
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "dev" : trimmed
    }
}
