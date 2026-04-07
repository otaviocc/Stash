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

/// `POST /app/import` multipart form — the selected format and the uploaded file.
struct ImportForm: Content {
    let format: String
    let file: File
}

/// `POST /app/settings/delete-all-bookmarks` form — the typed confirmation phrase.
struct DeleteAllBookmarksForm: Content {
    let confirm: String
}

/// `POST /app/settings/theme` form — the selected theme (`light` / `dark` / `auto`).
struct ThemeForm: Content {
    let theme: String
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
    let notice: String?
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

/// Summary of an import run, flashed across the post-import redirect.
struct ImportSummaryContext: Content {
    let imported: Int
    let updated: Int
    let skipped: Int
    let errors: [String]

    init(imported: Int, updated: Int, skipped: Int, errors: [String]) {
        self.imported = imported
        self.updated = updated
        self.skipped = skipped
        self.errors = errors
    }

    init(_ result: ImportResult) {
        self.init(imported: result.imported, updated: result.updated, skipped: result.skipped, errors: result.errors)
    }
}

struct AppSettingsContext: Content {
    let title: String
    let appUsername: String
    let isTOTPEnabled: Bool
    let error: String?
    let message: String?
    let importers: [FormatOption]
    let exporters: [FormatOption]
    let importError: String?
    let importSummary: ImportSummaryContext?
    /// Current theme preference: `light`, `dark`, or `auto`.
    let theme: String
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
