// MIT License
//
// Copyright (c) 2026 Otávio C.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Vapor

// MARK: - CreateBookmarkForm

/// `POST /app/bookmarks` form. `action` is "preview" (fetch metadata, don't save) or "save".
/// `tags` is a free-text field split on commas/whitespace.
struct CreateBookmarkForm: Content {

    let action: String?
    let url: String
    let title: String?
    let description: String?
    let tags: String?
}

// MARK: - EditBookmarkForm

/// `POST /app/bookmarks/:id` (edit). URL is not editable here. `archived` is an HTML checkbox
/// (present only when ticked).
struct EditBookmarkForm: Content {

    let title: String?
    let description: String?
    let tags: String?
    let archived: String?
}

// MARK: - AppChangePasswordForm

/// `POST /app/settings/password` form.
struct AppChangePasswordForm: Content {

    let currentPassword: String
    let newPassword: String
}

// MARK: - AppVerifyTOTPForm

/// `POST /app/settings/totp/verify` form.
struct AppVerifyTOTPForm: Content {

    let totpCode: String
}

// MARK: - AppDisableTOTPForm

/// `POST /app/settings/totp/disable` form. Requires the current TOTP code to confirm the user
/// still has access to their authenticator before turning 2FA off.
struct AppDisableTOTPForm: Content {

    let totpCode: String
}

// MARK: - ImportForm

/// `POST /app/import` multipart form — the selected format and the uploaded file.
struct ImportForm: Content {

    let format: String
    let file: File
}

// MARK: - DeleteAllBookmarksForm

/// `POST /app/settings/delete-all-bookmarks` form — the typed confirmation phrase.
struct DeleteAllBookmarksForm: Content {

    let confirm: String
}

// MARK: - ThemeForm

/// `POST /app/settings/theme` form — the selected theme (`light` / `dark` / `auto`).
struct ThemeForm: Content {

    let theme: String
}

// MARK: - TagLink

/// A tag rendered both as it is stored (`swift/vapor`) and for display (`swift › vapor`).
struct TagLink: Content {

    let name: String
    let display: String
}

// MARK: - SidebarTag

/// One row of the flattened, pre-ordered tag tree shown in the bookmark-list sidebar.
struct SidebarTag: Content {

    /// Just this level's label, e.g. `vapor`.
    let label: String
    /// Pre-built, percent-encoded link, e.g. `/app?tag=swift%2Fvapor`.
    let href: String
    /// Exact bookmark count for this tag (0 for synthetic parents that aren't a tag themselves).
    let count: Int
    /// Nesting depth (0 = top level), for indentation.
    let depth: Int
    /// Whether this is the currently active `?tag=` filter.
    let isActive: Bool
}

// MARK: - AppBookmarkRow

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

// MARK: - AppBookmarksContext

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
    let sidebarTags: [SidebarTag]
    /// Number of bookmarks with no tags (for the sidebar's "Untagged" item).
    let untaggedCount: Int
    /// Whether the current filter is the "Untagged" pseudo-tag.
    let untaggedActive: Bool
}

// MARK: - AppNewBookmarkContext

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

// MARK: - AppEditBookmarkContext

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

// MARK: - AppBookmarkDetailContext

struct AppBookmarkDetailContext: Content {

    let title: String
    let appUsername: String
    let bookmark: AppBookmarkRow
    let message: String?
}

// MARK: - AppTagCount

struct AppTagCount: Content {

    let name: String
    let display: String
    let count: Int
}

// MARK: - AppTagsContext

struct AppTagsContext: Content {

    let title: String
    let appUsername: String
    let tags: [AppTagCount]
    let message: String?
    let error: String?
}

/// `POST /app/tags/rename` form — `from` (hidden, the current tag) and `to` (the new name).
struct TagRenameForm: Content {
    let from: String
    let to: String
}

// MARK: - ImportSummaryContext

/// Summary of an import run, flashed across the post-import redirect.
struct ImportSummaryContext: Content {

    // MARK: Properties

    let imported: Int
    let updated: Int
    let skipped: Int
    let errors: [String]

    // MARK: Lifecycle

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

// MARK: - AppSettingsContext

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

// MARK: - AppTOTPSetupContext

struct AppTOTPSetupContext: Content {

    let title: String
    let appUsername: String
    let secret: String
    let otpauthURI: String
    let error: String?
}

// MARK: - AppRecoveryCodesContext

struct AppRecoveryCodesContext: Content {

    let title: String
    let appUsername: String
    let codes: [String]
}
