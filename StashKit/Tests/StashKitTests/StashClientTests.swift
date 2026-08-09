// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import MicroClient
import Testing
@testable import StashKit

// MARK: - StashClientTests

/// Verifies that `StashClient.run` decodes successful responses and maps failed responses
/// to the correct `StashAPIError` cases.
@Suite("StashClient: run and error mapping")
struct StashClientTests {

    // MARK: Static Properties

    /// Each API error `code` paired with the HTTP status the server returns for it.
    static let errorCases: [(code: String, status: Int)] = [
        ("invalid_credentials", 401),
        ("account_suspended", 401),
        ("token_expired", 401),
        ("token_invalid", 401),
        ("totp_required", 401),
        ("totp_invalid", 401),
        ("forbidden", 403),
        ("not_found", 404),
        ("username_taken", 409),
        ("validation_failed", 422),
        ("internal_error", 500)
    ]

    private static let baseURL = URL(string: "https://stash.test")!

    // MARK: Functions

    @Test("returns the decoded response model on a successful response")
    func decodesSuccess() async throws {
        // Given
        let id = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let json = """
        {
            "id": "\(id.uuidString)",
            "url": "https://example.com",
            "title": "Example",
            "description": null,
            "faviconURL": null,
            "tags": ["swift", "ios"],
            "isArchived": false,
            "waybackStatus": "none",
            "waybackURL": null,
            "waybackArchivedAt": null,
            "createdAt": "2026-01-01T00:00:00Z",
            "updatedAt": "2026-01-02T00:00:00Z"
        }
        """
        let client = makeClient(statusCode: 200, json: json)

        // When
        let response = try await client.run(BookmarkRequestFactory.makeGetRequest(id: id))

        // Then
        #expect(response.value.id == id, "It should decode the bookmark id")
        #expect(response.value.title == "Example", "It should decode the bookmark title")
        #expect(response.value.tags == ["swift", "ios"], "It should decode the bookmark tags")
        #expect(
            response.value.createdAt == Date(timeIntervalSince1970: 1_767_225_600),
            "It should decode the ISO-8601 createdAt date"
        )
    }

    @Test("sends the bearer token and the request's query items to the resolved URL")
    func buildsAuthorizedURL() async throws {
        // Given
        let session = MockURLSession(statusCode: 200, json: #"{"items":[],"metadata":{"page":1,"per":20,"total":0}}"#)
        let client = StashClient(baseURL: Self.baseURL, session: session) { "access-token" }
        let query = BookmarkListQuery(searchQuery: "swift", page: 2)

        // When
        _ = try await client.run(BookmarkRequestFactory.makeListRequest(query: query))

        // Then
        let sent = session.lastRequest
        #expect(
            sent?.url?.absoluteString.hasPrefix("https://stash.test/api/v1/bookmarks?") == true,
            "It should resolve the request path against the base URL"
        )
        #expect(sent?.url?.query?.contains("q=swift") == true, "It should append the search query item")
        #expect(sent?.url?.query?.contains("page=2") == true, "It should append the page query item")
        #expect(
            sent?.value(forHTTPHeaderField: "Authorization") == "Bearer access-token",
            "It should attach the bearer token provided by the token provider"
        )
    }

    @Test("maps a 409 duplicate_url response to .duplicateURL with the existing id")
    func mapsDuplicateURL() async throws {
        // Given
        let existingID = try #require(UUID(uuidString: "12345678-90AB-CDEF-1234-567890ABCDEF"))
        let json = """
        {
            "error": true,
            "code": "duplicate_url",
            "message": "This URL has already been saved.",
            "existingID": "\(existingID.uuidString)"
        }
        """
        let client = makeClient(statusCode: 409, json: json)

        // When
        let error = await capturedError(from: client)

        // Then
        guard case let .duplicateURL(returnedID) = error else {
            Issue.record("It should map a duplicate_url body to .duplicateURL")
            return
        }

        #expect(returnedID == existingID, "It should carry the existing bookmark's id")
    }

    @Test("maps each known error code to its StashAPIError case", arguments: errorCases)
    func mapsKnownErrorCode(_ errorCase: (code: String, status: Int)) async {
        // Given
        let json = #"{"error":true,"code":"\#(errorCase.code)","message":"x"}"#
        let client = makeClient(statusCode: errorCase.status, json: json)

        // When
        let error = await capturedError(from: client)

        // Then
        #expect(
            matches(error, code: errorCase.code),
            "It should map the \(errorCase.code) code to its matching StashAPIError case"
        )
    }

    // MARK: - Helpers

    private func makeClient(statusCode: Int, json: String) -> StashClient {
        let session = MockURLSession(statusCode: statusCode, json: json)

        return StashClient(baseURL: Self.baseURL, session: session) { nil }
    }

    private func capturedError(from client: StashClient) async -> StashAPIError? {
        do {
            _ = try await client.run(BookmarkRequestFactory.makeGetRequest(id: UUID()))
            return nil
        } catch let error as StashAPIError {
            return error
        } catch {
            return nil
        }
    }

    private func matches(_ error: StashAPIError?, code: String) -> Bool {
        switch (code, error) {
        case ("invalid_credentials", .invalidCredentials): true
        case ("account_suspended", .accountSuspended): true
        case ("token_expired", .tokenExpired): true
        case ("token_invalid", .tokenInvalid): true
        case ("totp_required", .totpRequired): true
        case ("totp_invalid", .totpInvalid): true
        case ("forbidden", .forbidden): true
        case ("not_found", .notFound): true
        case ("username_taken", .usernameTaken): true
        case ("validation_failed", .validationFailed): true
        case ("internal_error", .serverError): true
        default: false
        }
    }
}
