// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

extension EnvironmentValues {

    /// The instance's accent colour (see `InstanceAccent`), injected at the app root so custom
    /// components follow the server-configured theme instead of the static asset-catalog
    /// `Color.accentColor`. Defaults to the asset colour so `#Preview`s and the Share Extension
    /// (before it injects the shared value) render sensibly without this environment value set.
    @Entry var instanceAccent: Color = .accentColor

    /// Readable text for content sitting on a *solid* `instanceAccent` background (e.g.
    /// `TagCountBadge`). Defaults to white, matching the previous hardcoded behaviour.
    @Entry var instanceAccentTextColor: Color = .white

    /// The accent, nudged to stay legible when used as its *own* foreground/text/icon colour
    /// directly on the app's surface (e.g. a tag pill's label, a form row's tinted button) — as
    /// opposed to `instanceAccent`, which is the true brand colour for fills and washes. See
    /// `InstanceAccent.foregroundColor` for why the two differ.
    @Entry var instanceAccentForeground: Color = .accentColor
}
