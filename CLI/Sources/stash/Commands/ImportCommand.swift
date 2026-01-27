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

import ArgumentParser
import Foundation
import StashKit

// MARK: - ImportFormat + ExpressibleByArgument

extension ImportFormat: ExpressibleByArgument {}

// MARK: - ImportCommand

/// `stash import <file>` — import bookmarks from an Anybox or Stash JSON file.
///
/// The import endpoint is web-only (PRD §13), so the CLI re-implements it: it parses the file
/// locally and submits each record through the public bookmark API, creating new bookmarks and
/// updating existing ones (matched by the server's duplicate-URL response). A summary is printed.
struct ImportCommand: AsyncParsableCommand {

    // MARK: Static Properties

    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Import bookmarks from a file."
    )

    // MARK: Properties

    @Argument(help: "Path to the import file.")
    var file: String

    @Option(name: .customLong("format"), help: "Import format: anybox, stash-json.")
    var format: ImportFormat = .stashJSON

    // MARK: Functions

    func run() async throws {
        try await runCLI {
            let data = try readFile()
            let records = try ImportParser.parse(data, format: format)
            let client = try await CLIRuntime.authenticatedClient(store: ConfigStore())

            var imported = 0
            var updated = 0
            var skipped = 0

            for record in records {
                switch try await submit(record, client: client) {
                case .imported:
                    imported += 1
                case .updated:
                    updated += 1
                case .skipped:
                    skipped += 1
                }
            }

            Console.out("Imported: \(imported), Updated: \(updated), Skipped: \(skipped)")
        }
    }

    private func readFile() throws -> Data {
        guard let data = FileManager.default.contents(atPath: file) else {
            throw CLIError("Could not read file: \(file)")
        }

        return data
    }

    private func submit(_ record: ParsedBookmark, client: StashClient) async throws -> ImportOutcome {
        guard let url = record.url.flatMap(BookmarkInput.validatedURL) else {
            return .skipped
        }

        let tags = BookmarkInput.normalizeTags(record.tags)
        let description = record.description?.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let create = CreateBookmarkRequest(
                url: url,
                title: record.title,
                description: description?.isEmpty == true ? nil : description,
                tags: tags.isEmpty ? nil : tags,
                fetchMetadata: false
            )
            let bookmark = try await client.run(BookmarkRequestFactory.makeCreateRequest(create)).value

            if record.isArchived {
                let archive = UpdateBookmarkRequest(isArchived: true)
                _ = try await client.run(BookmarkRequestFactory.makeUpdateRequest(id: bookmark.id, body: archive))
            }

            return .imported
        } catch let StashAPIError.duplicateURL(existingID) {
            let update = UpdateBookmarkRequest(
                title: record.title,
                description: description?.isEmpty == true ? nil : description,
                tags: tags,
                isArchived: record.isArchived
            )
            _ = try await client.run(BookmarkRequestFactory.makeUpdateRequest(id: existingID, body: update))

            return .updated
        } catch {
            return .skipped
        }
    }
}

// MARK: - ImportOutcome

/// The result of submitting one parsed record during an import.
private enum ImportOutcome {

    case imported
    case updated
    case skipped
}
