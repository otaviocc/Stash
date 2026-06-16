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

import Fluent
import Foundation

// MARK: - SiteSettings

/// Instance-wide customization settings. A single-row table (never deleted): the admin's
/// chosen accent theme, an optional "About" message, and an optional custom footer link.
/// See the Site Settings & Admin Customisation section of `DECISIONS.md`.
final class SiteSettings: Model, @unchecked Sendable {

    // MARK: Static Properties

    static let schema = "site_settings"

    // MARK: Properties

    @ID(key: .id)
    var id: UUID?

    @Field(key: "accent_theme")
    var accentTheme: String

    @OptionalField(key: "about_text")
    var aboutText: String?

    @OptionalField(key: "footer_custom_label")
    var footerCustomLabel: String?

    @OptionalField(key: "footer_custom_url")
    var footerCustomURL: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    // MARK: Lifecycle

    init() {}

    init(
        id: UUID? = nil,
        accentTheme: String,
        aboutText: String? = nil,
        footerCustomLabel: String? = nil,
        footerCustomURL: String? = nil
    ) {
        self.id = id
        self.accentTheme = accentTheme
        self.aboutText = aboutText
        self.footerCustomLabel = footerCustomLabel
        self.footerCustomURL = footerCustomURL
    }
}
