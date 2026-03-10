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

// MARK: - FooterContext

/// Context passed to every page template for footer rendering. The Mastodon and Ko-fi links are
/// hardcoded directly in `_footer.leaf`, not passed here, so they cannot be accidentally omitted.
struct FooterContext: Content {

    let customLabel: String?
    let customURL: String?
    let version: String
}

// MARK: - SiteChrome

/// The instance-wide chrome injected into every page render under the `chrome` key: the resolved
/// accent colours (light/dark), the optional "About this instance" message, and the footer.
struct SiteChrome: Content {

    let footer: FooterContext
    let aboutText: String?
    let accentLight: String
    let accentDark: String
}

// MARK: - ThemeOption

/// One selectable accent theme rendered as a coloured circle in the appearance picker.
struct ThemeOption: Content {

    let id: String
    let name: String
    let color: String
    let isSelected: Bool
}

// MARK: - AppearanceContext

/// View context for the admin appearance page.
struct AppearanceContext: Content {

    let title: String
    let adminUsername: String
    let themes: [ThemeOption]
    let aboutText: String
    let footerCustomLabel: String
    let footerCustomURL: String
    let error: String?
    let message: String?
    let chrome: SiteChrome
}

// MARK: - AppearanceForm

/// `POST /admin/appearance` form — the chosen accent theme, the optional about message, and the
/// optional custom footer link.
struct AppearanceForm: Content {

    let accentTheme: String
    let aboutText: String?
    let footerCustomLabel: String?
    let footerCustomURL: String?
}
