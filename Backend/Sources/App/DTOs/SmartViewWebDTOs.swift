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

/// One condition row in the Smart View create/edit form, expanded for HTML rendering.
struct SmartViewConditionField: Content {

    let type: String
    let textValue: String
    let boolValue: String
    let isBool: Bool
    let isText: Bool
    let isDate: Bool
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
