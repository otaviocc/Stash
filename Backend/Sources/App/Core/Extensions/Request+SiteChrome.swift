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

extension Request {

    /// Builds the per-page chrome (footer + accent theme + about text) from the app-level settings
    /// cache. Never hits the database and never throws: a missing cache falls back to defaults so a
    /// page render is never blocked by a missing footer config.
    func siteChrome() -> SiteChrome {
        let snapshot = application.storage[SiteSettingsCacheKey.self]?.current ?? .default
        let version = application.storage[AppVersionKey.self] ?? "dev"
        let theme = AccentTheme.theme(for: snapshot.accentTheme)

        return SiteChrome(
            footer: FooterContext(
                customLabel: snapshot.footerCustomLabel.flatMap(\.nonEmpty),
                customURL: snapshot.footerCustomURL.flatMap(\.nonEmpty),
                version: version
            ),
            aboutText: snapshot.aboutText.flatMap(\.nonEmpty),
            accentLight: theme.light,
            accentDark: theme.dark
        )
    }
}
