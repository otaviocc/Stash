// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

/// Reads and writes the CLI configuration at `~/.config/stash/config.json`.
///
/// Loading a missing file yields an empty `CLIConfig` rather than an error, so first-run commands
/// can prompt for what they need. Saving creates the enclosing directory on demand and writes
/// atomically.
struct ConfigStore {

    // MARK: Properties

    let fileURL: URL

    // MARK: Lifecycle

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.fileURL = home.appending(path: ".config/stash/config.json")
        }
    }

    // MARK: Functions

    func load() throws -> CLIConfig {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return CLIConfig()
        }

        let data = try Data(contentsOf: fileURL)

        return try JSONDecoder().decode(CLIConfig.self, from: data)
    }

    func save(_ config: CLIConfig) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]

        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)
    }
}
