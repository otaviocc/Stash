// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Vapor

// MARK: - SidebarSmartView

/// A Smart View link rendered in the bookmark-list sidebar (above the tag tree).
struct SidebarSmartView: Content {

    let name: String
    let href: String
    let isActive: Bool
}

// MARK: - AppSmartViewRow

/// A Smart View rendered as a row in the management table.
struct AppSmartViewRow: Content {

    let id: String
    let name: String
    let summary: String
}

// MARK: - AppSmartViewsContext

/// View context for the Smart Views management page.
struct AppSmartViewsContext: Content {

    let title: String
    let appUsername: String
    let appIsAdmin: Bool
    let smartViews: [AppSmartViewRow]
    let message: String?
    let chrome: SiteChrome
}

// MARK: - SmartViewConditionField

/// One condition row in the Smart View create/edit form, expanded for HTML rendering. A row renders
/// exactly one value editor, selected by the flags: a text/date `<input>` (carrier named
/// `conditionValue[]`, its `textInputType` being `text`, `date`, or `hidden`), a Yes/No `<select>`,
/// or the compound duration control (`durationAmount` number + `durationUnit` selector, which a script
/// assembles into the hidden text carrier). The `hide…` flags are positive single-branch tests so the
/// Leaf template avoids the empty-then-branch gotcha (PRD §21).
struct SmartViewConditionField: Content {

    let type: String
    let textValue: String
    let boolValue: String
    let durationAmount: String
    let durationUnit: String
    let textInputType: String
    let isBool: Bool
    let hideBool: Bool
    let hideDuration: Bool
}

// MARK: - AppSmartViewFormContext

/// View context for the Smart View create/edit form.
struct AppSmartViewFormContext: Content {

    let title: String
    let appUsername: String
    let appIsAdmin: Bool
    let error: String?
    let isEdit: Bool
    let action: String
    let name: String
    let matchMode: String
    let conditions: [SmartViewConditionField]
    let knownTagsJSON: String
    let chrome: SiteChrome
}

// MARK: - SmartViewForm

/// `POST /app/smart-views/new` and `.../edit` form — the name and the parallel arrays of
/// condition types and values (the value comes from whichever input the row's type enables).
struct SmartViewForm: Content {

    let name: String
    let matchMode: String?
    let conditionType: [String]?
    let conditionValue: [String]?
}
