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
        case "password": "Password changed."
        case "totp_disabled": "Two-factor authentication disabled."
        case "theme": "Appearance updated."
        case "favicon_refreshing": "Favicon refresh started — it may take a moment to update."
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
        default: nil
        }
    }
}
