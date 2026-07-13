// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation
import Vapor

// MARK: - InstanceBackup

/// The full-instance backup envelope: every account (with its auth material so logins and 2FA
/// survive a restore), everyone's bookmarks and Smart Views, and the instance-wide site settings.
///
/// Deliberately excludes refresh tokens (session state — everyone simply signs back in), the
/// favicon cache (regenerable), and the audit log (operational history, not user data). Because it
/// carries password hashes, TOTP secrets, and recovery-code hashes verbatim, the exported file is
/// sensitive — treat it like a database dump, not a per-user export.
struct InstanceBackup: Codable, Sendable {

    let version: String
    let exportedAt: String
    let siteSettings: BackupSiteSettings
    let users: [BackupUser]
}

// MARK: - BackupSiteSettings

struct BackupSiteSettings: Codable, Sendable {

    let accentTheme: String
    let aboutText: String?
    let footerCustomLabel: String?
    let footerCustomURL: String?
    let internetArchiveEnabled: Bool
    let updateCheckEnabled: Bool
}

// MARK: - BackupUser

struct BackupUser: Codable, Sendable {

    let username: String
    let passwordHash: String
    let totpSecret: String?
    let isTOTPEnabled: Bool
    let role: String
    let isActive: Bool
    let archiveNewBookmarks: Bool
    let createdAt: String?
    let recoveryCodes: [BackupRecoveryCode]
    let bookmarks: [BackupBookmark]
    let smartViews: [BackupSmartView]
}

// MARK: - BackupRecoveryCode

struct BackupRecoveryCode: Codable, Sendable {

    let codeHash: String
    let usedAt: String?
}

// MARK: - BackupBookmark

struct BackupBookmark: Codable, Sendable {

    let url: String
    let title: String
    let description: String?
    let tags: [String]
    let faviconURL: String?
    let isArchived: Bool
    let createdAt: String
    let updatedAt: String
}

// MARK: - BackupSmartView

struct BackupSmartView: Codable, Sendable {

    let name: String
    let matchMode: String
    let conditions: [BackupCondition]
}

// MARK: - BackupCondition

struct BackupCondition: Codable, Sendable {

    let type: String
    let value: String
}

// MARK: - RestoreResult

/// Outcome of a restore run. Mirrors `ImportResult`'s two-tier split: a malformed file throws
/// (`InstanceBackupError.invalidFormat`), while individual bad records are counted in `skipped`
/// rather than aborting the whole restore.
struct RestoreResult: Sendable {

    let usersCreated: Int
    let usersMerged: Int
    let bookmarksImported: Int
    let bookmarksUpdated: Int
    let smartViewsImported: Int
    let smartViewsUpdated: Int
    let skipped: [String]
}

// MARK: - InstanceBackupError

/// Thrown when the uploaded file can't be parsed as a Stash instance backup at all. Individual bad
/// user/bookmark/Smart View records are reported via `RestoreResult.skipped`, not by throwing.
enum InstanceBackupError: Error, CustomStringConvertible {

    case invalidFormat(String)

    // MARK: Computed Properties

    var description: String {
        switch self {
        case let .invalidFormat(message): message
        }
    }
}

// MARK: - InstanceBackupService

/// Admin-only, instance-wide backup/restore — deliberately separate from the per-user
/// `ImportExportRegistry` (`StashJSONExporter`/`StashJSONImporter`), which is scoped to one
/// `userID` and surfaced under `/app`. This follows the same dedup-by-URL / dedup-by-name upsert
/// rules those use (see `StashJSONImporter`, the sibling implementation this restore path
/// deliberately mirrors), so a restored library behaves identically to one built up through normal
/// use.
enum InstanceBackupService {

    // MARK: Static Properties

    private static let iso = ISO8601DateFormatter()

    // MARK: Static Functions

    // MARK: - Export

    static func export(on db: any Database) async throws -> Data {
        let settings = try await SiteSettingsService.current(on: db)
        let users = try await User.query(on: db).sort(\.$username).all()
        let userIDs = try users.map { try $0.requireID() }

        // Batched once across every user rather than 3 queries per user: this is a single-shot,
        // admin-triggered read, but a self-hosted instance can still have enough users/bookmarks
        // that 3N+1 sequential round-trips would be noticeably slower than 4 total.
        let allBookmarks = try await Bookmark.query(on: db)
            .filter(\.$user.$id ~~ userIDs)
            .sort(\.$createdAt, .ascending)
            .sort(\.$id, .ascending)
            .all()
        let bookmarksByUser = Dictionary(grouping: allBookmarks, by: \.$user.id)

        let allSmartViews = try await SmartView.query(on: db)
            .filter(\.$user.$id ~~ userIDs)
            .sort(\.$name, .ascending)
            .all()
        let smartViewsByUser = Dictionary(grouping: allSmartViews, by: \.$user.id)

        let allRecoveryCodes = try await RecoveryCode.query(on: db)
            .filter(\.$user.$id ~~ userIDs)
            .all()
        let recoveryCodesByUser = Dictionary(grouping: allRecoveryCodes, by: \.$user.id)

        let backupUsers = try users.map { user -> BackupUser in
            let userID = try user.requireID()

            let bookmarkItems = (bookmarksByUser[userID] ?? []).map { bookmark in
                BackupBookmark(
                    url: bookmark.url,
                    title: bookmark.title,
                    description: bookmark.description,
                    tags: bookmark.tags,
                    faviconURL: bookmark.faviconURL,
                    isArchived: bookmark.isArchived,
                    createdAt: iso.string(from: bookmark.createdAt ?? Date()),
                    updatedAt: iso.string(from: bookmark.updatedAt ?? Date())
                )
            }

            let smartViewItems = (smartViewsByUser[userID] ?? []).map { smartView in
                BackupSmartView(
                    name: smartView.name,
                    matchMode: smartView.matchMode,
                    conditions: smartView.conditions.map {
                        BackupCondition(type: $0.typeString, value: $0.valueString)
                    }
                )
            }

            let recoveryCodeItems = (recoveryCodesByUser[userID] ?? []).map {
                BackupRecoveryCode(codeHash: $0.codeHash, usedAt: $0.usedAt.map { iso.string(from: $0) })
            }

            return BackupUser(
                username: user.username,
                passwordHash: user.passwordHash,
                totpSecret: user.totpSecret,
                isTOTPEnabled: user.isTOTPEnabled,
                role: user.role.rawValue,
                isActive: user.isActive,
                archiveNewBookmarks: user.archiveNewBookmarks,
                createdAt: iso.string(from: user.createdAt ?? Date()),
                recoveryCodes: recoveryCodeItems,
                bookmarks: bookmarkItems,
                smartViews: smartViewItems
            )
        }

        let backup = InstanceBackup(
            version: "1",
            exportedAt: iso.string(from: Date()),
            siteSettings: BackupSiteSettings(
                accentTheme: settings.accentTheme,
                aboutText: settings.aboutText,
                footerCustomLabel: settings.footerCustomLabel,
                footerCustomURL: settings.footerCustomURL,
                internetArchiveEnabled: settings.internetArchiveEnabled,
                updateCheckEnabled: settings.updateCheckEnabled
            ),
            users: backupUsers
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(backup)
    }

    // MARK: - Restore

    /// Merges a backup into the running instance, keyed by `username`. Never deletes a user absent
    /// from the backup. An **existing** user's account fields (password hash, TOTP, role, active
    /// state) are left untouched — only their bookmarks/Smart Views are merged — which is what makes
    /// the currently signed-in admin's own account self-lockout-proof by construction: it always
    /// already exists, so its own auth/role/active fields are never among the ones this restore can
    /// change. A **new** user is created with its backed-up account fields written verbatim
    /// (`passwordHash`/`totpSecret`/recovery-code hashes are stored as-is, never re-hashed, since
    /// they're already hashed in the backup).
    ///
    /// The whole merge runs inside one database transaction: an error partway through (a bad DB
    /// connection, a constraint violation) rolls back every write this call made rather than
    /// leaving the instance in a half-restored state with no record of what happened.
    static func restore(from data: Data, on app: Application) async throws -> RestoreResult {
        let backup: InstanceBackup
        do {
            backup = try JSONDecoder().decode(InstanceBackup.self, from: data)
        } catch {
            throw InstanceBackupError
                .invalidFormat(
                    "This doesn't look like a Stash instance backup (expected an object with a \"users\" array)."
                )
        }

        let settings = try await SiteSettingsService.current(on: app.db)

        let result = try await app.db.transaction { db -> RestoreResult in
            settings.accentTheme = backup.siteSettings.accentTheme
            settings.aboutText = backup.siteSettings.aboutText
            settings.footerCustomLabel = backup.siteSettings.footerCustomLabel
            settings.footerCustomURL = backup.siteSettings.footerCustomURL
            settings.internetArchiveEnabled = backup.siteSettings.internetArchiveEnabled
            settings.updateCheckEnabled = backup.siteSettings.updateCheckEnabled
            try await settings.save(on: db)

            // Preload every username the backup could match, plus their existing bookmarks/Smart
            // Views keyed for O(1) lookup, so the per-record loop below never issues its own
            // per-item existence-check query — the dictionaries are then kept up to date as new
            // records are created, so a duplicate URL/name within the same backup file still
            // merges correctly instead of hitting a unique-constraint violation.
            let candidateUsernames = backup.users.map {
                $0.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            let matchedUsers = try await User.query(on: db).filter(\.$username ~~ candidateUsernames).all()
            var usersByUsername = Dictionary(uniqueKeysWithValues: matchedUsers.map { ($0.username, $0) })

            let matchedUserIDs = try matchedUsers.map { try $0.requireID() }
            let existingBookmarks = try await Bookmark.query(on: db).filter(\.$user.$id ~~ matchedUserIDs).all()
            var bookmarksByUser: [UUID: [String: Bookmark]] = [:]
            for bookmark in existingBookmarks {
                bookmarksByUser[bookmark.$user.id, default: [:]][bookmark.url] = bookmark
            }

            let existingSmartViews = try await SmartView.query(on: db).filter(\.$user.$id ~~ matchedUserIDs).all()
            var smartViewsByUser: [UUID: [String: SmartView]] = [:]
            for smartView in existingSmartViews {
                smartViewsByUser[smartView.$user.id, default: [:]][smartView.name] = smartView
            }

            var usersCreated = 0
            var usersMerged = 0
            var bookmarksImported = 0
            var bookmarksUpdated = 0
            var smartViewsImported = 0
            var smartViewsUpdated = 0
            var skipped: [String] = []

            for backupUser in backup.users {
                let username = backupUser.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !username.isEmpty else {
                    skipped.append("A user record was missing a username.")
                    continue
                }

                let user: User
                if let existing = usersByUsername[username] {
                    user = existing
                    usersMerged += 1
                } else {
                    let created = User(
                        username: username,
                        passwordHash: backupUser.passwordHash,
                        role: UserRole(rawValue: backupUser.role) ?? .user,
                        isActive: backupUser.isActive,
                        isTOTPEnabled: backupUser.isTOTPEnabled,
                        totpSecret: backupUser.totpSecret,
                        archiveNewBookmarks: backupUser.archiveNewBookmarks
                    )
                    try await created.save(on: db)
                    if let createdAt = FlexibleISO8601.date(from: backupUser.createdAt) {
                        created.createdAt = createdAt
                        try await created.save(on: db)
                    }
                    for code in backupUser.recoveryCodes {
                        try await RecoveryCode(
                            userID: created.requireID(),
                            codeHash: code.codeHash,
                            usedAt: FlexibleISO8601.date(from: code.usedAt)
                        ).save(on: db)
                    }
                    user = created
                    usersByUsername[username] = created
                    usersCreated += 1
                }

                let userID = try user.requireID()
                var importedForUser = 0

                for (index, item) in backupUser.bookmarks.enumerated() {
                    let position = index + 1
                    let url: String
                    do {
                        url = try Bookmark.validatedURL(item.url)
                    } catch {
                        skipped.append("\(username) / bookmark \(position): invalid URL \u{201C}\(item.url)\u{201D}.")
                        continue
                    }

                    let tags = Bookmark.normalizeTags(item.tags)
                    if let existingBookmark = bookmarksByUser[userID]?[url] {
                        existingBookmark.title = item.title
                        existingBookmark.description = item.description
                        existingBookmark.applyTags(tags)
                        existingBookmark.isArchived = item.isArchived
                        existingBookmark.faviconURL = item.faviconURL
                        try await existingBookmark.save(on: db)
                        bookmarksUpdated += 1
                    } else {
                        let bookmark = Bookmark(
                            userID: userID,
                            url: url,
                            title: item.title,
                            description: item.description,
                            faviconURL: item.faviconURL,
                            tags: tags,
                            isArchived: item.isArchived
                        )
                        try await bookmark.save(on: db)
                        if let createdAt = FlexibleISO8601.date(from: item.createdAt) {
                            bookmark.createdAt = createdAt
                            try await bookmark.save(on: db)
                        }
                        bookmarksByUser[userID, default: [:]][url] = bookmark
                        bookmarksImported += 1
                        importedForUser += 1
                    }
                }

                if importedForUser > 0 {
                    user.bookmarkCount += importedForUser
                    try await user.save(on: db)
                }

                for (index, item) in backupUser.smartViews.enumerated() {
                    let position = index + 1
                    let name: String
                    let matchMode: String
                    let conditions: [SmartViewCondition]
                    do {
                        name = try SmartViewController.validatedName(item.name)
                        matchMode = try SmartViewController.validatedMatchMode(item.matchMode)
                        conditions = try SmartViewController.validatedConditions(
                            item.conditions.map { SmartViewConditionPayload(type: $0.type, value: $0.value) }
                        )
                    } catch {
                        let reason = (error as? APIError)?.reason ?? "could not be imported."
                        skipped.append("\(username) / Smart View \(position): \(reason)")
                        continue
                    }

                    if let existingSmartView = smartViewsByUser[userID]?[name] {
                        existingSmartView.matchMode = matchMode
                        existingSmartView.conditions = conditions
                        try await existingSmartView.save(on: db)
                        smartViewsUpdated += 1
                    } else {
                        let smartView = SmartView(
                            userID: userID, name: name, conditions: conditions, matchMode: matchMode
                        )
                        try await smartView.save(on: db)
                        smartViewsByUser[userID, default: [:]][name] = smartView
                        smartViewsImported += 1
                    }
                }
            }

            return RestoreResult(
                usersCreated: usersCreated,
                usersMerged: usersMerged,
                bookmarksImported: bookmarksImported,
                bookmarksUpdated: bookmarksUpdated,
                smartViewsImported: smartViewsImported,
                smartViewsUpdated: smartViewsUpdated,
                skipped: skipped
            )
        }

        SiteSettingsService.refreshCache(with: settings, on: app)
        return result
    }
}
