import Vapor

// MARK: - Form inputs (application/x-www-form-urlencoded)

/// `POST /app/bookmarks` form. `action` is "preview" (fetch metadata, don't save) or "save".
/// `tags` is a free-text field split on commas/whitespace.
struct CreateBookmarkForm: Content {
    let action: String?
    let url: String
    let title: String?
    let description: String?
    let tags: String?
}

/// `POST /app/bookmarks/:id` (edit). URL is not editable here. `archived` is an HTML checkbox
/// (present only when ticked).
struct EditBookmarkForm: Content {
    let title: String?
    let description: String?
    let tags: String?
    let archived: String?
}

/// `POST /app/settings/password` form.
struct AppChangePasswordForm: Content {
    let currentPassword: String
    let newPassword: String
}

/// `POST /app/settings/totp/verify` form.
struct AppVerifyTOTPForm: Content {
    let totpCode: String
}

/// `POST /app/settings/totp/disable` form. Requires the current TOTP code to confirm the user
/// still has access to their authenticator before turning 2FA off.
struct AppDisableTOTPForm: Content {
    let totpCode: String
}

// MARK: - Leaf view contexts

/// A tag rendered both as it is stored (`swift/vapor`) and for display (`swift › vapor`).
struct TagLink: Content {
    let name: String
    let display: String
}

struct AppBookmarkRow: Content {
    let id: String
    let url: String
    let title: String
    let description: String?
    let faviconURL: String?
    let tags: [TagLink]
    let isArchived: Bool
    let createdAt: String
}

struct AppBookmarksContext: Content {
    let title: String
    let appUsername: String
    let bookmarks: [AppBookmarkRow]
    let q: String
    let tag: String
    let tagDisplay: String
    let archived: Bool
    let total: Int
    let page: Int
    let pageCount: Int
    let prevURL: String?
    let nextURL: String?
}

struct AppNewBookmarkContext: Content {
    let title: String
    let appUsername: String
    let error: String?
    let existingID: String?
    let url: String
    let bookmarkTitle: String
    let description: String
    let tags: String
    let previewed: Bool
    /// JSON array of the user's existing tag names, for client-side autocomplete.
    let knownTagsJSON: String
}

struct AppEditBookmarkContext: Content {
    let title: String
    let appUsername: String
    let error: String?
    let id: String
    let url: String
    let bookmarkTitle: String
    let description: String
    let tags: String
    let isArchived: Bool
    /// JSON array of the user's existing tag names, for client-side autocomplete.
    let knownTagsJSON: String
}

struct AppBookmarkDetailContext: Content {
    let title: String
    let appUsername: String
    let bookmark: AppBookmarkRow
    let message: String?
}

struct AppTagCount: Content {
    let name: String
    let display: String
    let count: Int
}

struct AppTagsContext: Content {
    let title: String
    let appUsername: String
    let tags: [AppTagCount]
}

struct AppSettingsContext: Content {
    let title: String
    let appUsername: String
    let isTOTPEnabled: Bool
    let error: String?
    let message: String?
}

struct AppTOTPSetupContext: Content {
    let title: String
    let appUsername: String
    let secret: String
    let otpauthURI: String
    let error: String?
}

struct AppRecoveryCodesContext: Content {
    let title: String
    let appUsername: String
    let codes: [String]
}
