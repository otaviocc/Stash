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
