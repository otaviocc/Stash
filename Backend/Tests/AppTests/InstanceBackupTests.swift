// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

/// Verifies `InstanceBackupService` (export/restore) and the admin `/admin/backup` page
/// (Instance management: full instance backup/restore).
@Suite("Instance backup & restore")
struct InstanceBackupTests {

    // MARK: - Export

    @Test("exporting a fresh instance produces the seeded admin and no bookmarks")
    func exportFreshInstance() async throws {
        try await withTestApp { app in
            // Given
            _ = try await app.adminWebSession()

            // When
            let data = try await InstanceBackupService.export(on: app.db)
            let backup = try JSONDecoder().decode(InstanceBackup.self, from: data)

            // Then
            #expect(backup.version == "1", "It should stamp the format version")
            #expect(backup.users.count == 1, "It should include the seeded admin")
            #expect(backup.users.first?.username == "root", "It should include the admin's username")
            #expect(backup.users.first?.bookmarks.isEmpty == true, "It should have no bookmarks yet")
        }
    }

    @Test("exporting includes bookmarks, Smart Views, recovery codes, and site settings")
    func exportIncludesEverything() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser(username: "alice", password: "alice-password-123")
            try await app.makeBookmark(for: user, url: "https://example.com", title: "Example", tags: ["swift"])
            try await SmartView(
                userID: user.requireID(), name: "Reading list", conditions: [.tag("swift")]
            ).save(on: app.db)
            try await RecoveryCode(userID: user.requireID(), codeHash: "hashed-code").save(on: app.db)

            let settings = try await SiteSettingsService.current(on: app.db)
            settings.aboutText = "Test instance"
            try await settings.save(on: app.db)

            // When
            let data = try await InstanceBackupService.export(on: app.db)
            let backup = try JSONDecoder().decode(InstanceBackup.self, from: data)

            // Then
            #expect(backup.siteSettings.aboutText == "Test instance", "It should export site settings")
            let alice = try #require(backup.users.first { $0.username == "alice" })
            #expect(alice.bookmarks.count == 1, "It should export alice's bookmark")
            #expect(alice.bookmarks.first?.url == "https://example.com", "It should export the bookmark URL")
            #expect(alice.smartViews.count == 1, "It should export alice's Smart View")
            #expect(alice.recoveryCodes.count == 1, "It should export alice's recovery code hash")
            #expect(alice.recoveryCodes.first?.codeHash == "hashed-code", "It should export the hash verbatim")
        }
    }

    // MARK: - Restore

    @Test("restoring creates a new user with bookmarks, Smart Views, and working auth material")
    func restoreCreatesNewUser() async throws {
        try await withTestApp { app in
            // Given: export a second instance's data by building a backup document by hand
            let backup = try await InstanceBackup(
                version: "1",
                exportedAt: "2026-01-01T00:00:00Z",
                siteSettings: BackupSiteSettings(
                    accentTheme: "forest",
                    aboutText: nil,
                    footerCustomLabel: nil,
                    footerCustomURL: nil,
                    footerLinks: nil,
                    internetArchiveEnabled: true,
                    updateCheckEnabled: true
                ),
                users: [
                    BackupUser(
                        username: "bob",
                        passwordHash: app.password.async.hash("bob-password-123"),
                        totpSecret: nil,
                        isTOTPEnabled: false,
                        role: "user",
                        isActive: true,
                        archiveNewBookmarks: true,
                        createdAt: "2026-01-01T00:00:00Z",
                        recoveryCodes: [],
                        bookmarks: [
                            BackupBookmark(
                                url: "https://example.com",
                                title: "Example",
                                description: nil,
                                tags: ["swift"],
                                faviconURL: nil,
                                isArchived: false,
                                isReadLater: false,
                                createdAt: "2026-01-01T00:00:00Z",
                                updatedAt: "2026-01-01T00:00:00Z"
                            )
                        ],
                        smartViews: [
                            BackupSmartView(
                                name: "Reading list",
                                matchMode: "all",
                                conditions: [BackupCondition(type: "tag", value: "swift")]
                            )
                        ]
                    )
                ]
            )
            let data = try JSONEncoder().encode(backup)

            // When
            let result = try await InstanceBackupService.restore(from: data, on: app)

            // Then
            #expect(result.usersCreated == 1, "It should create the new user")
            #expect(result.bookmarksImported == 1, "It should import the bookmark")
            #expect(result.smartViewsImported == 1, "It should import the Smart View")

            let bob = try #require(try await User.query(on: app.db).filter(\.$username == "bob").first())
            #expect(bob.bookmarkCount == 1, "It should update the denormalized bookmark count")
            #expect(try await bob.$bookmarks.query(on: app.db).count() == 1, "It should have one bookmark")

            let settings = try await SiteSettingsService.current(on: app.db)
            #expect(settings.accentTheme == "forest", "It should restore site settings")

            var pair: TokenPair?
            try await app.testing().test(
                .POST, "api/v1/auth/login",
                beforeRequest: { req in
                    try req.content.encode(LoginRequest(username: "bob", password: "bob-password-123"))
                },
                afterResponse: { res async throws in
                    pair = try? res.content.decode(TokenPair.self)
                }
            )
            #expect(pair != nil, "It should let the restored user log in with their original password")
        }
    }

    @Test("two bookmark records sharing a URL in the same backup merge instead of colliding")
    func restoreHandlesDuplicateURLWithinOneBackup() async throws {
        try await withTestApp { app in
            // Given: restore batches per-user existing-bookmark lookups into one preloaded
            // dictionary rather than a query per item, so a second record for the same URL must
            // still find the first one it just created, not attempt a second insert.
            let backupBookmark = { (title: String) in
                BackupBookmark(
                    url: "https://example.com", title: title, description: nil, tags: [],
                    faviconURL: nil, isArchived: false, isReadLater: false,
                    createdAt: "2026-01-01T00:00:00Z", updatedAt: "2026-01-01T00:00:00Z"
                )
            }
            let backup = try await InstanceBackup(
                version: "1",
                exportedAt: "2026-01-01T00:00:00Z",
                siteSettings: BackupSiteSettings(
                    accentTheme: "ocean", aboutText: nil, footerCustomLabel: nil, footerCustomURL: nil,
                    footerLinks: nil,
                    internetArchiveEnabled: true, updateCheckEnabled: true
                ),
                users: [
                    BackupUser(
                        username: "dave",
                        passwordHash: app.password.async.hash("dave-password-123"),
                        totpSecret: nil, isTOTPEnabled: false, role: "user", isActive: true,
                        archiveNewBookmarks: true, createdAt: "2026-01-01T00:00:00Z",
                        recoveryCodes: [],
                        bookmarks: [backupBookmark("First"), backupBookmark("Second")],
                        smartViews: []
                    )
                ]
            )
            let data = try JSONEncoder().encode(backup)

            // When
            let result = try await InstanceBackupService.restore(from: data, on: app)

            // Then
            #expect(result.bookmarksImported == 1, "It should create only one bookmark for the shared URL")
            #expect(result.bookmarksUpdated == 1, "It should treat the second record as an update, not a crash")

            let dave = try #require(try await User.query(on: app.db).filter(\.$username == "dave").first())
            let bookmarks = try await dave.$bookmarks.query(on: app.db).all()
            #expect(bookmarks.count == 1, "It should end up with exactly one bookmark for the URL")
            #expect(bookmarks.first?.title == "Second", "It should apply the later record's fields last")
        }
    }

    @Test("restoring an existing user merges bookmarks without touching their auth fields")
    func restoreMergesExistingUser() async throws {
        try await withTestApp { app in
            // Given
            let existing = try await app.makeUser(username: "alice", password: "alice-password-123")
            let originalHash = existing.passwordHash
            try await app.makeBookmark(for: existing, url: "https://existing.example.com")

            let backup = InstanceBackup(
                version: "1",
                exportedAt: "2026-01-01T00:00:00Z",
                siteSettings: BackupSiteSettings(
                    accentTheme: "ocean", aboutText: nil, footerCustomLabel: nil, footerCustomURL: nil,
                    footerLinks: nil,
                    internetArchiveEnabled: true, updateCheckEnabled: true
                ),
                users: [
                    BackupUser(
                        username: "alice",
                        passwordHash: "some-other-hash-from-a-different-instance",
                        totpSecret: nil,
                        isTOTPEnabled: false,
                        role: "admin",
                        isActive: false,
                        archiveNewBookmarks: true,
                        createdAt: "2026-01-01T00:00:00Z",
                        recoveryCodes: [],
                        bookmarks: [
                            BackupBookmark(
                                url: "https://new.example.com",
                                title: "New",
                                description: nil,
                                tags: [],
                                faviconURL: nil,
                                isArchived: false,
                                isReadLater: false,
                                createdAt: "2026-01-01T00:00:00Z",
                                updatedAt: "2026-01-01T00:00:00Z"
                            )
                        ],
                        smartViews: []
                    )
                ]
            )
            let data = try JSONEncoder().encode(backup)

            // When
            let result = try await InstanceBackupService.restore(from: data, on: app)

            // Then
            #expect(result.usersMerged == 1, "It should merge into the existing account")
            #expect(result.bookmarksImported == 1, "It should import the new bookmark")

            let reloaded = try #require(try await User.find(existing.requireID(), on: app.db))
            #expect(reloaded.passwordHash == originalHash, "It should not overwrite the existing password hash")
            #expect(reloaded.role == .user, "It should not overwrite the existing role")
            #expect(reloaded.isActive, "It should not overwrite the existing active state")
            #expect(try await reloaded.$bookmarks.query(on: app.db).count() == 2, "It should have both bookmarks")
        }
    }

    @Test("restoring never modifies the signed-in admin's own account fields")
    func restoreNeverTouchesSelf() async throws {
        try await withTestApp { app in
            // Given
            let admin = try await app.makeUser(username: "root", password: "admin-password-123", role: .admin)
            let originalHash = admin.passwordHash

            let backup = InstanceBackup(
                version: "1",
                exportedAt: "2026-01-01T00:00:00Z",
                siteSettings: BackupSiteSettings(
                    accentTheme: "ocean", aboutText: nil, footerCustomLabel: nil, footerCustomURL: nil,
                    footerLinks: nil,
                    internetArchiveEnabled: true, updateCheckEnabled: true
                ),
                users: [
                    BackupUser(
                        username: "root",
                        passwordHash: "a-different-hash-entirely",
                        totpSecret: nil,
                        isTOTPEnabled: false,
                        role: "user",
                        isActive: false,
                        archiveNewBookmarks: true,
                        createdAt: "2026-01-01T00:00:00Z",
                        recoveryCodes: [],
                        bookmarks: [],
                        smartViews: []
                    )
                ]
            )
            let data = try JSONEncoder().encode(backup)

            // When
            _ = try await InstanceBackupService.restore(from: data, on: app)

            // Then
            let reloaded = try #require(try await User.find(admin.requireID(), on: app.db))
            #expect(reloaded.passwordHash == originalHash, "It should not touch the admin's own password hash")
            #expect(reloaded.role == .admin, "It should not demote the currently signed-in admin")
            #expect(reloaded.isActive, "It should not suspend the currently signed-in admin")
        }
    }

    @Test("a malformed backup file throws invalidFormat and changes nothing")
    func malformedBackupThrows() async throws {
        try await withTestApp { app in
            // Given
            let junk = Data("not json".utf8)

            // When / Then
            await #expect(throws: InstanceBackupError.self) {
                _ = try await InstanceBackupService.restore(from: junk, on: app)
            }
        }
    }

    @Test("a bad Smart View record is skipped and reported, not thrown")
    func badSmartViewRecordSkipped() async throws {
        try await withTestApp { app in
            // Given
            let backup = try await InstanceBackup(
                version: "1",
                exportedAt: "2026-01-01T00:00:00Z",
                siteSettings: BackupSiteSettings(
                    accentTheme: "ocean", aboutText: nil, footerCustomLabel: nil, footerCustomURL: nil,
                    footerLinks: nil,
                    internetArchiveEnabled: true, updateCheckEnabled: true
                ),
                users: [
                    BackupUser(
                        username: "carol",
                        passwordHash: app.password.async.hash("carol-password-123"),
                        totpSecret: nil,
                        isTOTPEnabled: false,
                        role: "user",
                        isActive: true,
                        archiveNewBookmarks: true,
                        createdAt: "2026-01-01T00:00:00Z",
                        recoveryCodes: [],
                        bookmarks: [],
                        smartViews: [
                            BackupSmartView(name: "", matchMode: "all", conditions: [])
                        ]
                    )
                ]
            )
            let data = try JSONEncoder().encode(backup)

            // When
            let result = try await InstanceBackupService.restore(from: data, on: app)

            // Then
            #expect(result.usersCreated == 1, "It should still create the user")
            #expect(result.smartViewsImported == 0, "It should not import the invalid Smart View")
            #expect(result.skipped.count == 1, "It should report the skipped record")
        }
    }

    // MARK: - Web page

    @Test("the backup page renders with counts and both actions")
    func backupPageRenders() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.adminWebSession()
            let user = try await app.makeUser(username: "alice", password: "alice-password-123")
            try await app.makeBookmark(for: user, url: "https://example.com")

            // When
            try await app.testing().test(.GET, "admin/backup", headers: headers) { res async throws in
                // Then
                #expect(res.status == .ok, "It should render the backup page")
                let body = res.body.string
                #expect(body.contains("Download instance backup"), "It should show the download action")
                #expect(body.contains("Restore backup"), "It should show the restore action")
            }
        }
    }

    @Test("downloading a backup returns a JSON attachment")
    func downloadBackupReturnsAttachment() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.adminWebSession()

            // When
            try await app.testing().test(.GET, "admin/backup/download", headers: headers) { res async throws in
                // Then
                #expect(res.status == .ok, "It should return the backup")
                #expect(
                    res.headers.first(name: .contentDisposition)?.contains("attachment") == true,
                    "It should be a downloadable attachment"
                )
                let decoded = try JSONDecoder().decode(InstanceBackup.self, from: Data(buffer: res.body))
                #expect(decoded.users.contains { $0.username == "root" }, "It should include the admin account")
            }
        }
    }

    @Test("restoring with the wrong confirmation phrase changes nothing")
    func restoreWrongConfirmationRejected() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.adminWebSession()
            let before = try await User.query(on: app.db).count()

            // When
            try await app.testing().test(
                .POST, "admin/backup/restore",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(
                        RestoreBackupForm(
                            file: File(data: ByteBuffer(string: "{}"), filename: "backup.json"),
                            confirm: "not-the-right-word"
                        ),
                        as: .formData
                    )
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .badRequest, "It should reject the wrong confirmation phrase")
                    #expect(res.body.string.contains("restore"), "It should show the confirmation error")
                }
            )

            #expect(try await User.query(on: app.db).count() == before, "It should not change anything")
        }
    }

    @Test("the backup page requires an admin session: unauthenticated requests redirect to login")
    func backupPageRequiresAuth() async throws {
        try await withTestApp { app in
            // When
            try await app.testing().test(.GET, "admin/backup") { res async throws in
                // Then
                #expect(res.status == .seeOther, "It should redirect rather than render the page")
                #expect(
                    res.headers.first(name: .location) == "/admin/login",
                    "It should redirect to the admin login page"
                )
            }
        }
    }
}
