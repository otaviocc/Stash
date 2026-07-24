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
}
