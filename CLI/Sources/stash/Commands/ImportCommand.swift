// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import ArgumentParser
import Foundation
import StashKit

// MARK: - ImportFormat + ExpressibleByArgument

extension ImportFormat: ExpressibleByArgument {}

// MARK: - ImportCommand

/// `stash import <file>` — import bookmarks from an Anybox or Stash JSON file.
///
/// The import endpoint is web-only (PRD §13), so the CLI re-implements it: it parses the file
/// locally and submits each record through the public API, creating new bookmarks and updating
/// existing ones (matched by the server's duplicate-URL response). A Stash JSON file's Smart Views
/// are also restored, matched by name. A summary is printed.
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
            let parsed = try ImportParser.parse(data, format: format)
            let client = try await CLIRuntime.authenticatedClient(store: ConfigStore())

            var imported = 0
            var updated = 0
            var skipped = 0

            for record in parsed.bookmarks {
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

            if !parsed.smartViews.isEmpty {
                try await importSmartViews(parsed.smartViews, client: client)
            }
        }
    }

    private func importSmartViews(_ smartViews: [ParsedSmartView], client: AuthorizedClient) async throws {
        let existing = try await client.run(SmartViewRequestFactory.makeListRequest()).value
        var idsByName = Dictionary(existing.map { ($0.name, $0.id) }) { first, _ in first }

        var imported = 0
        var updated = 0
        var skipped = 0
        var errors: [String] = []

        for (index, smartView) in smartViews.enumerated() {
            let position = index + 1

            guard let name = smartView.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  !smartView.conditions.isEmpty
            else {
                skipped += 1
                errors.append("Smart View \(position): missing a name or conditions.")
                continue
            }

            let body = SmartViewRequest(
                name: name,
                conditions: smartView.conditions,
                matchMode: smartView.matchMode ?? "all"
            )

            do {
                if let id = idsByName[name] {
                    _ = try await client.run(SmartViewRequestFactory.makeUpdateRequest(id: id, body: body))
                    updated += 1
                } else {
                    let created = try await client.run(SmartViewRequestFactory.makeCreateRequest(body)).value
                    idsByName[name] = created.id
                    imported += 1
                }
            } catch let error where CLIErrorReporter.abortsBatch(error) {
                throw error
            } catch {
                skipped += 1
                errors.append("Smart View \(position) (“\(name)”): \(CLIErrorReporter.message(for: error))")
            }
        }

        Console.out("Smart Views — Imported: \(imported), Updated: \(updated), Skipped: \(skipped)")
        for line in errors {
            Console.error(line)
        }
    }

    private func readFile() throws -> Data {
        guard let data = FileManager.default.contents(atPath: file) else {
            throw CLIError("Could not read file: \(file)")
        }

        return data
    }

    private func submit(_ record: ParsedBookmark, client: AuthorizedClient) async throws -> ImportOutcome {
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
        } catch let error where CLIErrorReporter.abortsBatch(error) {
            throw error
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
