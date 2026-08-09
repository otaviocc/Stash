// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// A small, dependency-free RFC 4180-ish CSV reader/writer, used by `RaindropCSVImporter`/
/// `RaindropCSVExporter`. Handles the cases real exports actually use: quoted fields, commas and
/// newlines embedded inside quoted fields, `""`-escaped quotes, and an optional UTF-8 BOM (common
/// in CSVs produced by spreadsheet tools), matching this backend's existing "dependency-free"
/// approach to text formats (see `MetadataFetcher`'s regex-based HTML scanning).
enum CSVParser {

    /// Parses `text` into rows of fields. The first row is not treated specially here; callers
    /// that expect a header row should read `rows.first`.
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var field = ""
        var insideQuotes = false

        var chars = Substring(text)
        if let first = chars.first, first == "\u{FEFF}" {
            chars.removeFirst()
        }

        var iterator = chars.makeIterator()
        var pending = iterator.next()

        func peekNext() -> Character? {
            iterator.next()
        }

        while let char = pending {
            if insideQuotes {
                if char == "\"" {
                    let next = peekNext()
                    if next == "\"" {
                        field.append("\"")
                        pending = peekNext()
                    } else {
                        insideQuotes = false
                        pending = next
                    }
                } else {
                    field.append(char)
                    pending = peekNext()
                }
            } else {
                switch char {
                case "\"":
                    insideQuotes = true
                    pending = peekNext()
                case ",":
                    currentRow.append(field)
                    field = ""
                    pending = peekNext()
                case "\r":
                    let next = peekNext()
                    currentRow.append(field)
                    field = ""
                    rows.append(currentRow)
                    currentRow = []
                    pending = next == "\n" ? peekNext() : next
                case "\n":
                    currentRow.append(field)
                    field = ""
                    rows.append(currentRow)
                    currentRow = []
                    pending = peekNext()
                default:
                    field.append(char)
                    pending = peekNext()
                }
            }
        }

        if !field.isEmpty || !currentRow.isEmpty {
            currentRow.append(field)
            rows.append(currentRow)
        }

        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }

    /// Quotes `field` if it contains a comma, quote, or newline; escapes embedded quotes as `""`.
    static func quote(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }

        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    /// Joins already-quoted-as-needed fields into one CSV line (no trailing newline).
    static func makeLine(_ fields: [String]) -> String {
        fields.map(quote).joined(separator: ",")
    }
}
