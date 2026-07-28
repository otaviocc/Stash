// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Maps the Post/Redirect/Get `?ok=` / `?notice=` query flags to the human-readable banner copy shown
/// across the web UIs. Centralizes the flash-message wording for both the user frontend (`/app`) and
/// the admin dashboard (`/admin`).
enum FlashMessage {

    /// Success banners for the user-facing frontend (`/app?...&ok=`).
    static func app(for ok: String?) -> String? {
        switch ok {
        case "created": "Bookmark saved."
        case "saved": "Changes saved."
        case "archived": "Bookmark archived."
        case "unarchived": "Bookmark unarchived."
        case "read_later": "Marked to read later."
        case "marked_read": "Marked as read."
        case "password": "Password changed."
        case "totp_disabled": "Two-factor authentication disabled."
        case "theme": "Appearance updated."
        case "favicon_refreshing": "Favicon refresh started — it may take a moment to update."
        case "archive_pref": "Preference saved."
        case "wayback_started": "Sending to the Wayback Machine — it may take a moment to update."
        default: nil
        }
    }

    /// Error banners for the user-facing frontend (`/app?...&error=`).
    static func appError(for error: String?) -> String? {
        switch error {
        case "internet_archive_disabled": "Internet Archive submissions are disabled instance-wide."
        default: nil
        }
    }

    /// Standalone notices for the user frontend (`/app?notice=`).
    static func notice(for value: String?) -> String? {
        switch value {
        case "all_bookmarks_deleted": "All your bookmarks were deleted."
        default: nil
        }
    }

    /// Success banners for the admin dashboard (`/admin/...?ok=`).
    static func admin(for ok: String?) -> String? {
        switch ok {
        case "created": "User created."
        case "suspended": "User suspended; their sessions were revoked."
        case "unsuspended": "User reactivated."
        case "password-reset": "Password reset; the user's sessions were revoked."
        case "totp_reset": "Two-factor authentication reset; the user must set it up again and was signed out."
        case "db_optimized": "Database optimize complete."
        case "favicons_cleared": "Favicon cache cleared. Use Re-scan to rebuild it, or save a new bookmark for a domain."
        case "favicons_rescanning": "Re-scan started; this runs in the background and may take a while."
        case "sessions-revoked-all": "All sessions revoked. Everyone will need to sign in again."
        case "sessions-revoked-user": "Sessions revoked; the user will need to sign in again."
        case "ia_saved": "Internet Archive setting saved."
        case "ia_retrying": "Retrying failed submissions; this runs in the background."
        case "ia_queued": "Queued every bookmark for submission; this runs in the background and may take a while."
        case "ia_resumed": "Queue nudged — it will pick up any queued bookmarks shortly."
        case "update_checked": "Update check complete."
        case "update_check_skipped": "Update check skipped — checking is disabled or already in progress."
        case "backup_restored": "Restore complete."
        case "updates_enabled": "Update checking enabled."
        case "updates_disabled": "Update checking disabled."
        default: nil
        }
    }

    /// Error banners for the admin dashboard (`/admin/...?error=`).
    static func adminError(for error: String?) -> String? {
        switch error {
        case "unsupported_driver": "Could not access the database for maintenance (unsupported driver)."
        case "vacuum_failed": "Database optimize failed. Check the server logs for details."
        case "internet_archive_disabled": "Internet Archive submissions are disabled instance-wide. Enable them above first."
        case "restore_confirm": #"Type "restore" to confirm — nothing was restored."#
        case "restore_file_missing": "Please choose a backup file to restore."
        case "restore_invalid": "That file doesn't look like a Stash instance backup."
        default: nil
        }
    }
}
