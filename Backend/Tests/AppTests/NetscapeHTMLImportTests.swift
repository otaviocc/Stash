// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

/// Verifies `NetscapeHTMLImporter`: folder-nesting → hierarchical tags, the non-standard `TAGS`
/// attribute, `ADD_DATE`/`DD` handling, entity decoding, duplicate-URL updates, and parse failures.
///
/// The nested-folder fixture below mirrors a real Chrome-style export (unclosed `<DT>`/`<p>`,
/// three levels of folders) rather than a synthetic one.
@Suite("Netscape HTML import")
struct NetscapeHTMLImportTests {

    // MARK: - Folders

    @Test("importing nested folders produces a hierarchical tag per bookmark")
    func importsNestedFoldersAsHierarchicalTags() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let html = """
            <!DOCTYPE NETSCAPE-Bookmark-file-1>
            <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
            <TITLE>Bookmarks</TITLE>
            <H1>Bookmarks</H1>
            <DL><p>
                <DT><H3 ADD_DATE="1611420722" LAST_MODIFIED="1650397116">Bookmarks Bar</H3>
                <DL><p>
                    <DT><A HREF="https://www.google.com/" ADD_DATE="1650397103">Google</A>
                    <DT><H3 ADD_DATE="1650397124">Github</H3>
                    <DL><p>
                        <DT><A HREF="https://github.com/reactjs/reactjs.org" ADD_DATE="1650397152">The React docs</A>
                    </DL><p>
                </DL><p>
                <DT><A HREF="https://zetcode.com/golang/net-html/" ADD_DATE="1650055527">Golang Net html</A>
            </DL><p>
            """
            let data = Data(html.utf8)

            // When
            let result = try await NetscapeHTMLImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            #expect(result.imported == 3, "It should import all three bookmarks")
            let google = try #require(
                try await Bookmark.query(on: app.db).filter(\.$url == "https://www.google.com/").first()
            )
            #expect(google.tags == ["bookmarks bar"], "It should tag a top-level bookmark with its folder")
            let react = try #require(
                try await Bookmark.query(on: app.db).filter(\.$url == "https://github.com/reactjs/reactjs.org").first()
            )
            #expect(react.tags == ["bookmarks bar/github"], "It should join nested folders with a slash")
            let net = try #require(
                try await Bookmark.query(on: app.db).filter(\.$url == "https://zetcode.com/golang/net-html/").first()
            )
            #expect(net.tags == [], "It should have no folder tag once both nested </DL>s return to the root level")
        }
    }

    // MARK: - TAGS attribute

    @Test("importing a non-standard TAGS attribute merges it with the folder tag")
    func importsTagsAttribute() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let html = """
            <!DOCTYPE NETSCAPE-Bookmark-file-1>
            <DL><p>
            <DT><A HREF="https://example.com" ADD_DATE="1414706885" TAGS="javascript,mac,osx">Example</A>
            </DL><p>
            """
            let data = Data(html.utf8)

            // When
            _ = try await NetscapeHTMLImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            let bookmark = try #require(try await Bookmark.query(on: app.db).first())
            #expect(bookmark.tags == ["javascript", "mac", "osx"], "It should split the TAGS attribute on commas")
        }
    }

    // MARK: - Descriptions

    @Test("importing a DD line attaches it as the preceding bookmark's description")
    func importsDDAsDescription() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let html = """
            <!DOCTYPE NETSCAPE-Bookmark-file-1>
            <DL><p>
            <DT><A HREF="https://example.com" ADD_DATE="1414706885">Example</A>
            <DD>A helpful description.
            <DT><A HREF="https://other.com" ADD_DATE="1414706885">Other</A>
            </DL><p>
            """
            let data = Data(html.utf8)

            // When
            _ = try await NetscapeHTMLImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            let example = try #require(
                try await Bookmark.query(on: app.db).filter(\.$url == "https://example.com").first()
            )
            #expect(
                example.$description.value == "A helpful description.",
                "It should attach the DD to the preceding bookmark"
            )
            let other = try #require(
                try await Bookmark.query(on: app.db).filter(\.$url == "https://other.com").first()
            )
            let otherDescription = try #require(other.$description.value, "description should be loaded")
            #expect(otherDescription == nil, "It should not carry a description over to the next bookmark")
        }
    }

    // MARK: - Dates

    @Test("importing ADD_DATE sets createdAt from Unix seconds")
    func importsAddDate() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let html = """
            <!DOCTYPE NETSCAPE-Bookmark-file-1>
            <DL><p>
            <DT><A HREF="https://example.com" ADD_DATE="1592222400">Example</A>
            </DL><p>
            """
            let data = Data(html.utf8)

            // When
            _ = try await NetscapeHTMLImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            let bookmark = try #require(try await Bookmark.query(on: app.db).first())
            #expect(
                bookmark.createdAt == Date(timeIntervalSince1970: 1_592_222_400),
                "It should parse ADD_DATE as Unix seconds"
            )
        }
    }

    // MARK: - Entities

    @Test("importing an HTML-entity-encoded title decodes it")
    func decodesEntitiesInTitle() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let html = """
            <!DOCTYPE NETSCAPE-Bookmark-file-1>
            <DL><p>
            <DT><A HREF="https://example.com" ADD_DATE="1414706885">Fish &amp; Chips</A>
            </DL><p>
            """
            let data = Data(html.utf8)

            // When
            _ = try await NetscapeHTMLImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            let bookmark = try #require(try await Bookmark.query(on: app.db).first())
            #expect(bookmark.title == "Fish & Chips", "It should decode the &amp; entity")
        }
    }

    // MARK: - Missing/invalid URLs

    @Test("importing an entry with a missing HREF skips it with an error")
    func skipsMissingHREF() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let html = """
            <!DOCTYPE NETSCAPE-Bookmark-file-1>
            <DL><p>
            <DT><A ADD_DATE="1414706885">No URL</A>
            <DT><A HREF="https://ok.com" ADD_DATE="1414706885">OK</A>
            </DL><p>
            """
            let data = Data(html.utf8)

            // When
            let result = try await NetscapeHTMLImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            #expect(result.imported == 1, "It should import the valid entry")
            #expect(result.skipped == 1, "It should skip the entry without an HREF")
        }
    }

    // MARK: - Duplicates

    @Test("importing a duplicate URL updates the existing bookmark in place")
    func updatesDuplicateURL() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let original = try await app.makeBookmark(
                for: user, url: "https://example.com", title: "Old", tags: ["old"]
            )
            let originalCreatedAt = original.createdAt
            let html = """
            <!DOCTYPE NETSCAPE-Bookmark-file-1>
            <DL><p>
            <DT><A HREF="https://example.com" ADD_DATE="1414706885" TAGS="new">New</A>
            </DL><p>
            """
            let data = Data(html.utf8)

            // When
            let result = try await NetscapeHTMLImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            #expect(result.updated == 1, "It should count the record as updated")
            let bookmark = try #require(try await Bookmark.find(original.requireID(), on: app.db))
            #expect(bookmark.title == "New", "It should overwrite the title")
            #expect(bookmark.tags == ["new"], "It should overwrite the tags")
            #expect(bookmark.createdAt == originalCreatedAt, "It should preserve the original createdAt")
        }
    }

    // MARK: - Counts & failures

    @Test("importing a file without the Netscape doctype throws invalidFormat")
    func throwsOnMissingDoctype() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let data = Data("<html><body>not a bookmarks file</body></html>".utf8)

            // When / Then
            await #expect(throws: ImportError.self, "It should reject a file without the doctype") {
                _ = try await NetscapeHTMLImporter().import(from: data, for: user.requireID(), on: app.db)
            }
        }
    }
}
