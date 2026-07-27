// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Testing
@testable import App

/// Verifies `CSVParser`: plain rows, quoted fields with embedded commas/newlines/escaped quotes,
/// a leading BOM, blank-line skipping, and the writer's round-trip through the reader.
@Suite("CSV parser")
struct CSVParserTests {

    // MARK: - Reading

    @Test("parsing plain comma-separated rows splits on commas")
    func parsesPlainRows() {
        // Given
        let text = "folder,url,title\nWork,https://example.com,Example"

        // When
        let rows = CSVParser.parse(text)

        // Then
        #expect(
            rows == [["folder", "url", "title"], ["Work", "https://example.com", "Example"]],
            "It should split plain rows"
        )
    }

    @Test("parsing a quoted field with an embedded comma keeps it as one field")
    func parsesQuotedCommaField() {
        // Given
        let text = #"folder,url,title,note,tags,created\#n"Folder",http://google.com,Google,"Note","search, app",1629980125"#

        // When
        let rows = CSVParser.parse(text)

        // Then
        #expect(rows.count == 2, "It should produce a header row and one data row")
        #expect(
            rows[1] == ["Folder", "http://google.com", "Google", "Note", "search, app", "1629980125"],
            "It should keep the quoted tags field intact"
        )
    }

    @Test("parsing a quoted field with an escaped quote unescapes it")
    func parsesEscapedQuote() {
        // Given
        let text = #"title\#n"She said ""hi"""#

        // When
        let rows = CSVParser.parse(text)

        // Then
        #expect(rows[1] == [#"She said "hi""#], "It should unescape doubled quotes")
    }

    @Test("parsing a quoted field with an embedded newline keeps it as one field")
    func parsesQuotedNewlineField() {
        // Given
        let text = "note\n\"line one\nline two\""

        // When
        let rows = CSVParser.parse(text)

        // Then
        #expect(rows[1] == ["line one\nline two"], "It should keep the embedded newline inside the quoted field")
    }

    @Test("parsing strips a leading UTF-8 BOM")
    func stripsLeadingBOM() {
        // Given
        let text = "\u{FEFF}url,title\nhttps://example.com,Example"

        // When
        let rows = CSVParser.parse(text)

        // Then
        #expect(rows.first?.first == "url", "It should strip the BOM from the first field")
    }

    @Test("parsing skips fully blank lines")
    func skipsBlankLines() {
        // Given
        let text = "url,title\n\nhttps://example.com,Example\n"

        // When
        let rows = CSVParser.parse(text)

        // Then
        #expect(rows.count == 2, "It should skip the blank line between rows")
    }

    @Test("parsing a file without a trailing newline still reads the last row")
    func parsesWithoutTrailingNewline() {
        // Given
        let text = "url,title\nhttps://example.com,Example"

        // When
        let rows = CSVParser.parse(text)

        // Then
        #expect(rows.count == 2, "It should read the final row even without a trailing newline")
        #expect(rows[1] == ["https://example.com", "Example"], "It should read all fields of the final row")
    }

    // MARK: - Writing

    @Test("quoting a field containing a comma wraps it in quotes")
    func quotesFieldWithComma() {
        #expect(CSVParser.quote("a, b") == "\"a, b\"", "It should quote a comma-containing field")
    }

    @Test("quoting a plain field leaves it unquoted")
    func doesNotQuotePlainField() {
        #expect(CSVParser.quote("plain") == "plain", "It should leave a plain field unquoted")
    }

    @Test("writing then reading a line round-trips the original fields")
    func roundTripsThroughParser() {
        // Given
        let fields = ["a, b", "she said \"hi\"", "line one\nline two", "plain"]

        // When
        let line = CSVParser.makeLine(fields)
        let rows = CSVParser.parse(line)

        // Then
        #expect(rows == [fields], "It should read back exactly the fields it wrote")
    }
}
