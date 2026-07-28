// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import StashKit

/// Verifies DTOs still decode responses from an older backend that predates later-added fields.
/// Stash is self-hosted, so the apps/CLI and a user's server update independently — a missing new
/// key must decode to its documented default, never fail the whole payload.
@Suite("DTO backward compatibility — old-server JSON")
struct DTOBackwardCompatibilityTests {

    // MARK: Computed Properties

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: Functions

    @Test("a bookmark without any wayback keys decodes with waybackStatus defaulting to none")
    func bookmarkWithoutWaybackKeysDecodes() throws {
        let json = """
        {
            "id": "7C9E6679-7425-40DE-944B-E07FC1F90AE7",
            "url": "https://example.com",
            "title": "Example",
            "tags": ["swift"],
            "isArchived": false,
            "createdAt": "2026-06-01T09:30:00Z",
            "updatedAt": "2026-06-01T09:30:00Z"
        }
        """

        let bookmark = try decoder.decode(BookmarkDTO.self, from: Data(json.utf8))

        #expect(bookmark.waybackStatus == WaybackStatusDTO.none, "It should default a missing waybackStatus to none")
        #expect(bookmark.waybackURL == nil, "It should default a missing waybackURL to nil")
        #expect(bookmark.waybackArchivedAt == nil, "It should default a missing waybackArchivedAt to nil")
        #expect(bookmark.title == "Example", "It should still decode the rest of the bookmark")
    }

    @Test("a bookmark without the isReadLater key decodes with it defaulting to false")
    func bookmarkWithoutReadLaterKeyDecodes() throws {
        let json = """
        {
            "id": "7C9E6679-7425-40DE-944B-E07FC1F90AE7",
            "url": "https://example.com",
            "title": "Example",
            "tags": ["swift"],
            "isArchived": false,
            "createdAt": "2026-06-01T09:30:00Z",
            "updatedAt": "2026-06-01T09:30:00Z"
        }
        """

        let bookmark = try decoder.decode(BookmarkDTO.self, from: Data(json.utf8))

        #expect(bookmark.isReadLater == false, "It should default a missing isReadLater to false")
        #expect(bookmark.title == "Example", "It should still decode the rest of the bookmark")
    }

    @Test("a user without the archiveNewBookmarks key decodes with the server-side default of true")
    func userWithoutArchivePreferenceDecodes() throws {
        let json = """
        {
            "id": "7C9E6679-7425-40DE-944B-E07FC1F90AE7",
            "username": "otavio",
            "role": "user",
            "isActive": true,
            "isTOTPEnabled": false,
            "bookmarkCount": 3,
            "createdAt": "2026-06-01T09:30:00Z"
        }
        """

        let user = try decoder.decode(UserDTO.self, from: Data(json.utf8))

        #expect(user.archiveNewBookmarks, "It should default a missing archiveNewBookmarks to true")
        #expect(user.username == "otavio", "It should still decode the rest of the user")
    }
}
