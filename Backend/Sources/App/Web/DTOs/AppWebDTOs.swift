// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Vapor

// MARK: - LandingPageContext

/// View context for the public landing page at `/` (unauthenticated). `aboutText` is surfaced
/// directly here — in addition to the footer copy carried by `chrome` — so the page can show an
/// "About this instance" card between the hero and the features when the admin has set one.
struct LandingPageContext: Content {

    let title: String
    let chrome: SiteChrome
    let aboutText: String?
}

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

/// `POST /app/bookmarks/:id` (edit). URL is not editable here.
struct EditBookmarkForm: Content {

    let title: String?
    let description: String?
    let tags: String?
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

// MARK: - ArchivePrefForm

/// `POST /app/settings/archive-pref` form. An unchecked HTML checkbox sends nothing, so this
/// decodes as an optional and is coalesced to `false`.
struct ArchivePrefForm: Content {

    let enabled: Bool?
}

// MARK: - TagLink

/// A tag rendered both as it is stored (`swift/vapor`) and for display (`swift › vapor`).
struct TagLink: Content {

    let name: String
    let display: String
}

// MARK: - SidebarTag

/// One row of the flattened, pre-ordered tag tree shown in the bookmark-list sidebar.
/// `count` is the visible (non-archived) tally; `totalCount` includes archived bookmarks, and
/// `hiddenCount` is their difference — so the sidebar can render the same split count badge as the
/// native apps (accent "visible" half, muted "hidden" half) without arithmetic in the template.
struct SidebarTag: Content {

    let label: String
    let href: String
    let count: Int
    let totalCount: Int
    let hiddenCount: Int
    let depth: Int
    let isActive: Bool
}

// MARK: - AppBookmarkRow

/// A bookmark rendered as a row in the web app's bookmark list.
struct AppBookmarkRow: Content {

    let id: String
    let url: String
    let title: String
    let description: String?
    let faviconDomain: String?
    let tags: [TagLink]
    let isArchived: Bool
    let waybackURL: String?
    let waybackStatus: String
    let createdAt: String
}

// MARK: - AppBookmarksContext

/// View context for the web app's bookmark list page.
struct AppBookmarksContext: Content {

    let title: String
    let appUsername: String
    let appIsAdmin: Bool
    let bookmarks: [AppBookmarkRow]
    let q: String
    let tag: String
    let tagDisplay: String
    let archived: Bool
    let archiveToggleURL: String
    let total: Int
    let page: Int
    let pageCount: Int
    let prevURL: String?
    let nextURL: String?
    let notice: String?
    let sidebarTags: [SidebarTag]
    let untaggedCount: Int
    let untaggedActive: Bool
    let todayCount: Int
    let todayActive: Bool
    let thisWeekCount: Int
    let thisWeekActive: Bool
    let smartViews: [SidebarSmartView]
    let isSmartView: Bool
    let smartViewID: String
    let showArchivedToggle: Bool
    let returnToParam: String
    let chrome: SiteChrome
}

// MARK: - AppNewBookmarkContext

/// View context for the web app's new-bookmark form page.
struct AppNewBookmarkContext: Content {

    let title: String
    let appUsername: String
    let appIsAdmin: Bool
    let error: String?
    let existingID: String?
    let url: String
    let bookmarkTitle: String
    let description: String
    let tags: String
    let previewed: Bool
    let knownTagsJSON: String
    let returnURL: String
    let returnToParam: String
    let chrome: SiteChrome
}

// MARK: - AppEditBookmarkContext

/// View context for the web app's edit-bookmark form page.
struct AppEditBookmarkContext: Content {

    let title: String
    let appUsername: String
    let appIsAdmin: Bool
    let error: String?
    let id: String
    let url: String
    let bookmarkTitle: String
    let description: String
    let tags: String
    let knownTagsJSON: String
    let returnToParam: String
    let chrome: SiteChrome
}

// MARK: - AppBookmarkDetailContext

/// View context for the web app's bookmark detail page.
struct AppBookmarkDetailContext: Content {

    let title: String
    let appUsername: String
    let appIsAdmin: Bool
    let bookmark: AppBookmarkRow
    let message: String?
    let error: String?
    let returnURL: String
    let returnToParam: String
    let chrome: SiteChrome
}

// MARK: - AppTagCount

/// A tag with its display label and bookmark count, for the web app's tag views.
struct AppTagCount: Content {

    let name: String
    let display: String
    let count: Int
}

// MARK: - AppTagsContext

/// View context for the web app's tags management page.
struct AppTagsContext: Content {

    let title: String
    let appUsername: String
    let appIsAdmin: Bool
    let tags: [AppTagCount]
    let message: String?
    let error: String?
    let chrome: SiteChrome
}

// MARK: - TagRenameForm

/// `POST /app/tags/rename` form — `from` (hidden, the current tag) and `to` (the new name).
struct TagRenameForm: Content {

    let from: String
    let to: String
}

// MARK: - TagDeleteForm

/// `POST /app/tags/delete` form — `tag` (hidden, the tag to delete with its children).
struct TagDeleteForm: Content {

    let tag: String
}

// MARK: - ImportSummaryContext

/// Summary of an import run, flashed across the post-import redirect.
struct ImportSummaryContext: Content {

    // MARK: Properties

    let imported: Int
    let updated: Int
    let skipped: Int
    let smartViewsImported: Int
    let smartViewsUpdated: Int
    let smartViewsSkipped: Int
    let hasSmartViews: Bool
    let errors: [String]

    // MARK: Lifecycle

    init(
        imported: Int,
        updated: Int,
        skipped: Int,
        smartViewsImported: Int,
        smartViewsUpdated: Int,
        smartViewsSkipped: Int,
        errors: [String]
    ) {
        self.imported = imported
        self.updated = updated
        self.skipped = skipped
        self.smartViewsImported = smartViewsImported
        self.smartViewsUpdated = smartViewsUpdated
        self.smartViewsSkipped = smartViewsSkipped
        hasSmartViews = smartViewsImported + smartViewsUpdated + smartViewsSkipped > 0
        self.errors = errors
    }

    init(_ result: ImportResult) {
        self.init(
            imported: result.imported,
            updated: result.updated,
            skipped: result.skipped,
            smartViewsImported: result.smartViewsImported,
            smartViewsUpdated: result.smartViewsUpdated,
            smartViewsSkipped: result.smartViewsSkipped,
            errors: result.errors
        )
    }
}

// MARK: - AppSettingsContext

/// View context for the web app's settings page.
struct AppSettingsContext: Content {

    let title: String
    let appUsername: String
    let appIsAdmin: Bool
    let isTOTPEnabled: Bool
    let error: String?
    let message: String?
    let importers: [FormatOption]
    let exporters: [FormatOption]
    let defaultImporter: String
    let defaultExporter: String
    let importError: String?
    let importSummary: ImportSummaryContext?
    let theme: String
    let archiveNewBookmarks: Bool
    let chrome: SiteChrome
}

// MARK: - AppTOTPSetupContext

/// View context for the web app's TOTP setup page.
struct AppTOTPSetupContext: Content {

    let title: String
    let appUsername: String
    let appIsAdmin: Bool
    let secret: String
    let otpauthURI: String
    let error: String?
    let chrome: SiteChrome
}

// MARK: - AppRecoveryCodesContext

/// View context for the web app's recovery codes page.
struct AppRecoveryCodesContext: Content {

    let title: String
    let appUsername: String
    let appIsAdmin: Bool
    let codes: [String]
    let chrome: SiteChrome
}
