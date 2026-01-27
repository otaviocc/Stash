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

// MARK: - ExportFormat

/// The file formats the CLI can export.
enum ExportFormat: String, CaseIterable, ExpressibleByArgument {

    case stashJSON = "stash-json"
}

// MARK: - ExportCommand

/// `stash export` — export all bookmarks (archived included) to a Stash JSON file.
///
/// Paginates through every page of both active and archived bookmarks, assembles the native export
/// envelope locally, and writes it to disk.
struct ExportCommand: AsyncParsableCommand {

    // MARK: Static Properties

    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export all bookmarks to a file."
    )

    // MARK: Properties

    @Option(name: .customLong("format"), help: "Export format: stash-json.")
    var format: ExportFormat = .stashJSON

    @Option(name: .customLong("output"), help: "Output file path.")
    var output: String?

    // MARK: Functions

    func run() async throws {
        try await runCLI {
            let client = try await CLIRuntime.authenticatedClient(store: ConfigStore())

            var bookmarks = try await fetchAll(archived: false, client: client)
            bookmarks += try await fetchAll(archived: true, client: client)

            let document = ExportDocument(bookmarks: bookmarks, exportedAt: Date())
            let data = try document.encoded()

            let path = output ?? defaultFileName()
            let url = URL(fileURLWithPath: path)
            try data.write(to: url, options: .atomic)

            Console.out("Exported \(bookmarks.count) bookmarks to \(path).")
        }
    }

    private func fetchAll(archived: Bool, client: StashClient) async throws -> [BookmarkDTO] {
        var all: [BookmarkDTO] = []
        var page = 1

        while true {
            let query = BookmarkListQuery(archived: archived, page: page, perPage: 100)
            let result = try await client.run(BookmarkRequestFactory.makeListRequest(query: query)).value
            all.append(contentsOf: result.items)

            if result.items.isEmpty || all.count >= result.metadata.total {
                break
            }

            page += 1
        }

        return all
    }

    private func defaultFileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        return "stash-export-\(formatter.string(from: Date())).json"
    }
}
